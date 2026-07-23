/*
 * steamwebhelper-wrapper - WineOnMac
 *
 * Steam's UI is Chromium (CEF). On Apple Silicon Wine, CEF's multi-process
 * GPU/compositor path can't present to winemac's surface, so the login and
 * library windows paint solid black. There is no Steam command-line flag that
 * forces CEF's *helper* process into a working mode - Steam spawns
 * steamwebhelper.exe itself with a fixed argument set.
 *
 * So we interpose: rename Steam's real helper to steamwebhelper_real.exe and
 * drop this wrapper in its place. When Steam launches "steamwebhelper.exe", it
 * gets us; we prepend two flags and delegate to the real binary:
 *
 *   --disable-gpu      Force CPU (Skia) rasterisation. Enough for Steam's 2D
 *                      UI, and avoids the GPU process that crash-loops on winemac.
 *   --single-process   Collapse renderer/utility/gpu into one process. Fixes both
 *                      (a) the black browser window and (b) the winsock TLS
 *                      handshake cascade from the out-of-process NetworkService.
 *
 * Build (needs mingw-w64):
 *   x86_64-w64-mingw32-gcc -municode -O2 -Wall -Wextra -static -mwindows \
 *     -o steamwebhelper-wrapper.exe steamwebhelper-wrapper.c
 *
 * Approach adapted from notpop/steam-on-m1-wine (MIT).
 */

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <stdlib.h>
#include <wchar.h>

#define EXTRA_FLAGS L"--disable-gpu --single-process"
#define REAL_BINARY L"steamwebhelper_real.exe"

/* Build "<dir-of-this-exe>\steamwebhelper_real.exe". Caller frees. */
static wchar_t *resolve_real(void)
{
    wchar_t self[MAX_PATH];
    DWORD len = GetModuleFileNameW(NULL, self, MAX_PATH);
    if (len == 0 || len >= MAX_PATH) return NULL;

    wchar_t *slash = wcsrchr(self, L'\\');
    if (!slash) return NULL;
    *(slash + 1) = L'\0';

    size_t cap = wcslen(self) + wcslen(REAL_BINARY) + 1;
    wchar_t *real = calloc(cap, sizeof(wchar_t));
    if (!real) return NULL;
    wcscpy(real, self);
    wcscat(real, REAL_BINARY);
    return real;
}

/* Return the argument portion of our command line (everything after argv[0]). */
static const wchar_t *args_tail(void)
{
    const wchar_t *cmd = GetCommandLineW();
    if (!cmd) return L"";
    int quoted = 0;
    while (*cmd) {
        if (*cmd == L'"') quoted = !quoted;
        else if (*cmd == L' ' && !quoted) break;
        ++cmd;
    }
    while (*cmd == L' ') ++cmd;
    return cmd;
}

int wmain(void)
{
    wchar_t *real = resolve_real();
    if (!real) return 1;

    const wchar_t *tail = args_tail();
    size_t cap = wcslen(real) + wcslen(EXTRA_FLAGS) + wcslen(tail) + 8;
    wchar_t *cmdline = calloc(cap, sizeof(wchar_t));
    if (!cmdline) { free(real); return 1; }
    _snwprintf(cmdline, cap, L"\"%ls\" %ls %ls", real, EXTRA_FLAGS, tail);

    STARTUPINFOW si; PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si)); si.cb = sizeof(si);
    ZeroMemory(&pi, sizeof(pi));

    if (!CreateProcessW(real, cmdline, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi)) {
        free(cmdline); free(real);
        return 1;
    }
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess); CloseHandle(pi.hThread);
    free(cmdline); free(real);
    return (int)code;
}
