/* cxtest.c - minimal ConnectEx + IOCP localhost reproducer.
 * Mirrors what gRPC's tcp_client_windows.cc does: overlapped ConnectEx on a
 * non-blocking socket to a localhost port, then wait for the IOCP completion.
 * On real Windows the completion is ALWAYS posted, even for an instant connect.
 * If Wine fails to post it for an instant localhost connect, GQCS times out ->
 * this is the "connect then immediately abandon" signature EA's BGS gRPC shows.
 */
#include <winsock2.h>
#include <ws2tcpip.h>
#include <mswsock.h>
#include <windows.h>
#include <stdio.h>

static GUID guid_connectex = WSAID_CONNECTEX;

static u_short server_port = 0;
static HANDLE  server_ready;

static DWORD WINAPI server_thread(LPVOID arg)
{
    SOCKET ls = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    struct sockaddr_in a; int len = sizeof(a);
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    a.sin_port = 0;
    bind(ls, (struct sockaddr*)&a, sizeof(a));
    listen(ls, 8);
    getsockname(ls, (struct sockaddr*)&a, &len);
    server_port = a.sin_port;
    printf("[server] listening on 127.0.0.1:%u\n", ntohs(server_port));
    fflush(stdout);
    SetEvent(server_ready);

    SOCKET cs = accept(ls, NULL, NULL);
    if (cs == INVALID_SOCKET) { printf("[server] accept failed %d\n", WSAGetLastError()); return 1; }
    printf("[server] ACCEPTED a connection\n"); fflush(stdout);
    /* simulate gRPC server sending its HTTP/2 SETTINGS preface */
    const char *settings = "\x00\x00\x00\x04\x00\x00\x00\x00\x00";
    send(cs, settings, 9, 0);
    printf("[server] sent 9-byte SETTINGS frame\n"); fflush(stdout);
    Sleep(500);
    closesocket(cs); closesocket(ls);
    return 0;
}

int main(void)
{
    WSADATA wsa; WSAStartup(MAKEWORD(2,2), &wsa);
    server_ready = CreateEventW(NULL, TRUE, FALSE, NULL);
    HANDLE th = CreateThread(NULL, 0, server_thread, NULL, 0, NULL);
    WaitForSingleObject(server_ready, INFINITE);

    HANDLE iocp = CreateIoCompletionPort(INVALID_HANDLE_VALUE, NULL, 0, 0);

    SOCKET s = WSASocketW(AF_INET, SOCK_STREAM, IPPROTO_TCP, NULL, 0, WSA_FLAG_OVERLAPPED);
    CreateIoCompletionPort((HANDLE)s, iocp, (ULONG_PTR)0xC0FFEE, 0);

    /* ConnectEx requires an explicitly bound socket */
    struct sockaddr_in la; memset(&la, 0, sizeof(la));
    la.sin_family = AF_INET; la.sin_addr.s_addr = htonl(INADDR_LOOPBACK); la.sin_port = 0;
    bind(s, (struct sockaddr*)&la, sizeof(la));

    /* make it non-blocking, exactly like gRPC */
    u_long nb = 1; ioctlsocket(s, FIONBIO, &nb);

    LPFN_CONNECTEX pConnectEx = NULL; DWORD got = 0;
    WSAIoctl(s, SIO_GET_EXTENSION_FUNCTION_POINTER, &guid_connectex, sizeof(guid_connectex),
             &pConnectEx, sizeof(pConnectEx), &got, NULL, NULL);
    if (!pConnectEx) { printf("[client] no ConnectEx ptr %d\n", WSAGetLastError()); return 2; }

    struct sockaddr_in ra; memset(&ra, 0, sizeof(ra));
    ra.sin_family = AF_INET; ra.sin_addr.s_addr = htonl(INADDR_LOOPBACK); ra.sin_port = server_port;

    OVERLAPPED ov; memset(&ov, 0, sizeof(ov));
    BOOL ok = pConnectEx(s, (struct sockaddr*)&ra, sizeof(ra), NULL, 0, NULL, &ov);
    int err = WSAGetLastError();
    printf("[client] ConnectEx returned %d, WSAGetLastError=%d %s\n",
           ok, err, ok ? "(IMMEDIATE success)" : (err==WSA_IO_PENDING ? "(pending)" : "(ERROR)"));
    fflush(stdout);

    if (!ok && err != WSA_IO_PENDING) { printf("[client] FAIL: ConnectEx error\n"); return 3; }

    DWORD bytes = 0; ULONG_PTR key = 0; LPOVERLAPPED pov = NULL;
    BOOL cok = GetQueuedCompletionStatus(iocp, &bytes, &key, &pov, 3000);
    if (cok) {
        printf("[client] *** IOCP COMPLETION RECEIVED *** key=0x%llx bytes=%lu  -> connect completion WORKS\n",
               (unsigned long long)key, bytes);
    } else {
        DWORD ge = GetLastError();
        if (pov == NULL && ge == WAIT_TIMEOUT)
            printf("[client] !!! NO IOCP COMPLETION (timeout) !!!  -> BUG REPRODUCED: instant localhost connect completion not posted\n");
        else
            printf("[client] GQCS returned failure: GetLastError=%lu pov=%p\n", ge, (void*)pov);
    }
    fflush(stdout);

    WaitForSingleObject(th, 2000);
    closesocket(s); WSACleanup();
    return 0;
}
