/* cxtest2.c - closer to gRPC: AcceptEx+IOCP server, ConnectEx+IOCP client,
 * plus the post-connect socket ops gRPC performs (SO_UPDATE_CONNECT_CONTEXT,
 * SO_ERROR, getpeername). Isolates which step Wine mishandles for localhost.
 */
#include <winsock2.h>
#include <ws2tcpip.h>
#include <mswsock.h>
#include <windows.h>
#include <stdio.h>

static GUID guid_connectex = WSAID_CONNECTEX;
static GUID guid_acceptex   = WSAID_ACCEPTEX;

int main(void)
{
    WSADATA wsa; WSAStartup(MAKEWORD(2,2), &wsa);

    HANDLE iocp = CreateIoCompletionPort(INVALID_HANDLE_VALUE, NULL, 0, 0);

    /* ---- SERVER: listen + AcceptEx (overlapped) ---- */
    SOCKET ls = WSASocketW(AF_INET, SOCK_STREAM, IPPROTO_TCP, NULL, 0, WSA_FLAG_OVERLAPPED);
    struct sockaddr_in a; int len = sizeof(a);
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET; a.sin_addr.s_addr = htonl(INADDR_LOOPBACK); a.sin_port = 0;
    bind(ls, (struct sockaddr*)&a, sizeof(a));
    listen(ls, 8);
    getsockname(ls, (struct sockaddr*)&a, &len);
    u_short port = a.sin_port;
    printf("[srv] listening 127.0.0.1:%u\n", ntohs(port)); fflush(stdout);
    CreateIoCompletionPort((HANDLE)ls, iocp, (ULONG_PTR)0xACCE, 0);

    SOCKET as = WSASocketW(AF_INET, SOCK_STREAM, IPPROTO_TCP, NULL, 0, WSA_FLAG_OVERLAPPED);
    LPFN_ACCEPTEX pAcceptEx = NULL; DWORD got = 0;
    WSAIoctl(ls, SIO_GET_EXTENSION_FUNCTION_POINTER, &guid_acceptex, sizeof(guid_acceptex),
             &pAcceptEx, sizeof(pAcceptEx), &got, NULL, NULL);
    char acceptbuf[2*(sizeof(struct sockaddr_in)+16)];
    OVERLAPPED aov; memset(&aov, 0, sizeof(aov));
    DWORD abytes = 0;
    BOOL aok = pAcceptEx(ls, as, acceptbuf, 0,
                         sizeof(struct sockaddr_in)+16, sizeof(struct sockaddr_in)+16, &abytes, &aov);
    printf("[srv] AcceptEx returned %d err=%d %s\n", aok, WSAGetLastError(),
           aok ? "(immediate)" : (WSAGetLastError()==WSA_IO_PENDING ? "(pending)" : "(ERROR)"));
    fflush(stdout);

    /* ---- CLIENT: ConnectEx (overlapped) ---- */
    SOCKET cs = WSASocketW(AF_INET, SOCK_STREAM, IPPROTO_TCP, NULL, 0, WSA_FLAG_OVERLAPPED);
    CreateIoCompletionPort((HANDLE)cs, iocp, (ULONG_PTR)0xC0FFEE, 0);
    struct sockaddr_in la; memset(&la, 0, sizeof(la));
    la.sin_family = AF_INET; la.sin_addr.s_addr = htonl(INADDR_LOOPBACK); la.sin_port = 0;
    bind(cs, (struct sockaddr*)&la, sizeof(la));
    u_long nb = 1; ioctlsocket(cs, FIONBIO, &nb);
    LPFN_CONNECTEX pConnectEx = NULL;
    WSAIoctl(cs, SIO_GET_EXTENSION_FUNCTION_POINTER, &guid_connectex, sizeof(guid_connectex),
             &pConnectEx, sizeof(pConnectEx), &got, NULL, NULL);
    struct sockaddr_in ra; memset(&ra, 0, sizeof(ra));
    ra.sin_family = AF_INET; ra.sin_addr.s_addr = htonl(INADDR_LOOPBACK); ra.sin_port = port;
    OVERLAPPED cov; memset(&cov, 0, sizeof(cov));
    BOOL cok = pConnectEx(cs, (struct sockaddr*)&ra, sizeof(ra), NULL, 0, NULL, &cov);
    printf("[cli] ConnectEx returned %d err=%d %s\n", cok, WSAGetLastError(),
           cok ? "(immediate)" : (WSAGetLastError()==WSA_IO_PENDING ? "(pending)" : "(ERROR)"));
    fflush(stdout);

    /* ---- Drain both completions ---- */
    int got_accept = 0, got_connect = 0;
    for (int i = 0; i < 2; i++) {
        DWORD bytes = 0; ULONG_PTR key = 0; LPOVERLAPPED pov = NULL;
        BOOL c = GetQueuedCompletionStatus(iocp, &bytes, &key, &pov, 3000);
        if (!c && pov == NULL) { printf("[iocp] TIMEOUT waiting for completion #%d (got_accept=%d got_connect=%d)\n", i, got_accept, got_connect); break; }
        printf("[iocp] completion key=0x%llx bytes=%lu ok=%d\n", (unsigned long long)key, bytes, c);
        if (key == 0xACCE) got_accept = 1;
        if (key == 0xC0FFEE) got_connect = 1;
        fflush(stdout);
    }
    printf("[result] AcceptEx completion posted: %s\n", got_accept ? "YES" : "NO  <-- server would never accept");
    printf("[result] ConnectEx completion posted: %s\n", got_connect ? "YES" : "NO");
    fflush(stdout);

    if (got_connect) {
        /* gRPC post-connect steps */
        int r = setsockopt(cs, SOL_SOCKET, SO_UPDATE_CONNECT_CONTEXT, NULL, 0);
        printf("[cli] SO_UPDATE_CONNECT_CONTEXT ret=%d err=%d\n", r, WSAGetLastError());
        int soerr = 0, sl = sizeof(soerr);
        getsockopt(cs, SOL_SOCKET, SO_ERROR, (char*)&soerr, &sl);
        printf("[cli] SO_ERROR=%d\n", soerr);
        struct sockaddr_in pn; int pl = sizeof(pn);
        int gp = getpeername(cs, (struct sockaddr*)&pn, &pl);
        printf("[cli] getpeername ret=%d err=%d peer=127.0.0.1:%u\n", gp, WSAGetLastError(), ntohs(pn.sin_port));
    }
    if (got_accept) {
        int r = setsockopt(as, SOL_SOCKET, SO_UPDATE_ACCEPT_CONTEXT, (char*)&ls, sizeof(ls));
        printf("[srv] SO_UPDATE_ACCEPT_CONTEXT ret=%d err=%d\n", r, WSAGetLastError());
    }
    fflush(stdout);

    WSACleanup();
    return 0;
}
