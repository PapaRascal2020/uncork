/*
 * Uncork steamwebhelper CEF shim.
 *
 * Steam's UI (login, library, store) is CEF/Chromium, hosted by steamwebhelper.exe.
 * On Apple Silicon under Wine, CEF's multi-process path delivers rendered frames over
 * a cross-process IPC (client_surface_present) that silently fails on some machines,
 * so the window renders BLACK. Forcing CEF into a SINGLE process with the GPU
 * disabled removes that cross-process step, so the UI renders.
 *
 * This shim takes the place of steamwebhelper.exe. It launches the real client
 * (steamwebhelper_real.exe, alongside it) with the original arguments, and for the
 * MAIN process appends our CEF flags. Arguments carrying --type= belong to CEF child
 * processes and are passed through unchanged. Flags come from UNCORK_CEF_FLAGS, or a
 * built-in default when unset.
 *
 * Technique credit: github.com/wisnuub/Steam-Win-Silicon (independently reimplemented).
 *
 * Build:
 *   x86_64-w64-mingw32-gcc -O2 -mwindows -o steamwebhelper-shim-64.exe steamwebhelper-shim.c
 *   i686-w64-mingw32-gcc   -O2 -mwindows -o steamwebhelper-shim-32.exe steamwebhelper-shim.c
 */
#include <windows.h>
#include <wchar.h>
#include <stdlib.h>

static const wchar_t *DEFAULT_FLAGS = L"--disable-gpu --single-process";

int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE hPrev, LPWSTR lpCmdLine, int nShow)
{
    (void)hInst; (void)hPrev; (void)lpCmdLine; (void)nShow;

    /* The real client sits next to us as steamwebhelper_real.exe. */
    wchar_t self[MAX_PATH];
    GetModuleFileNameW(NULL, self, MAX_PATH);
    wchar_t real[MAX_PATH];
    wcsncpy(real, self, MAX_PATH);
    real[MAX_PATH - 1] = L'\0';
    wchar_t *slash = wcsrchr(real, L'\\');
    if (slash) wcscpy(slash + 1, L"steamwebhelper_real.exe");
    else wcscpy(real, L"steamwebhelper_real.exe");

    /* Original command line, so we preserve the exact quoting of the real args. */
    wchar_t *orig = GetCommandLineW();

    /* Skip the argv[0] token to get the trailing arguments. */
    wchar_t *rest = orig;
    if (*rest == L'"') { rest++; while (*rest && *rest != L'"') rest++; if (*rest == L'"') rest++; }
    else { while (*rest && *rest != L' ') rest++; }

    /* CEF child processes carry --type=; leave those exactly as-is. */
    int is_child = (wcsstr(orig, L"--type=") != NULL);

    const wchar_t *flags = _wgetenv(L"UNCORK_CEF_FLAGS");
    if (!flags || !*flags) flags = DEFAULT_FLAGS;

    /* Build:  "<real>"<rest>[ <flags>] */
    size_t need = wcslen(real) + wcslen(rest) + wcslen(flags) + 8;
    wchar_t *cmd = (wchar_t *)malloc(need * sizeof(wchar_t));
    if (!cmd) return 1;
    wcscpy(cmd, L"\"");
    wcscat(cmd, real);
    wcscat(cmd, L"\"");
    wcscat(cmd, rest);
    if (!is_child) { wcscat(cmd, L" "); wcscat(cmd, flags); }

    STARTUPINFOW si; ZeroMemory(&si, sizeof(si)); si.cb = sizeof(si);
    PROCESS_INFORMATION pi; ZeroMemory(&pi, sizeof(pi));
    if (!CreateProcessW(real, cmd, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi)) {
        free(cmd);
        return 1;
    }
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 1;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    free(cmd);
    return (int)code;
}
