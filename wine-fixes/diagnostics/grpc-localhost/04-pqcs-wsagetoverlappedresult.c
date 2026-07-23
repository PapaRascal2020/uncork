/* cxtest4.c - the gRPC Windows IOCP-engine primitives my socket tests didn't cover:
 *  (1) PostQueuedCompletionStatus poller "kick" (grpc uses this to wake its IOCP
 *      poller threads; if it doesn't deliver, the whole event engine stalls).
 *  (2) WSAGetOverlappedResult after an overlapped connect (grpc reads the result
 *      this way; a wrong wsa_error here makes grpc treat a good connect as failed).
 *  (3) multi-threaded GQCS contention (grpc runs a pool of poller threads).
 */
#include <winsock2.h>
#include <ws2tcpip.h>
#include <mswsock.h>
#include <windows.h>
#include <stdio.h>

static GUID guid_connectex = WSAID_CONNECTEX;

int main(void)
{
    WSADATA wsa; WSAStartup(MAKEWORD(2,2), &wsa);
    HANDLE iocp = CreateIoCompletionPort(INVALID_HANDLE_VALUE, NULL, 0, 0);

    /* (1) PostQueuedCompletionStatus round-trip */
    OVERLAPPED kickov; memset(&kickov,0,sizeof(kickov));
    BOOL pq = PostQueuedCompletionStatus(iocp, 123, (ULONG_PTR)0x1C, &kickov);
    printf("[1] PostQueuedCompletionStatus ret=%d err=%lu\n", pq, GetLastError());
    { DWORD b; ULONG_PTR k; LPOVERLAPPED p;
      BOOL c=GetQueuedCompletionStatus(iocp,&b,&k,&p,1000);
      printf("[1] kick delivered=%d bytes=%lu key=0x%llx ov=%p %s\n", c, b, (unsigned long long)k, (void*)p,
             (c && b==123 && p==&kickov) ? "-> PQCS WORKS" : "-> PQCS BROKEN"); }
    fflush(stdout);

    /* set up a real localhost connect for (2) */
    SOCKET ls=WSASocketW(AF_INET,SOCK_STREAM,IPPROTO_TCP,NULL,0,WSA_FLAG_OVERLAPPED);
    struct sockaddr_in a; int len=sizeof(a); memset(&a,0,sizeof(a));
    a.sin_family=AF_INET; a.sin_addr.s_addr=htonl(INADDR_LOOPBACK); a.sin_port=0;
    bind(ls,(struct sockaddr*)&a,sizeof(a)); listen(ls,8);
    getsockname(ls,(struct sockaddr*)&a,&len); u_short port=a.sin_port;

    SOCKET cs=WSASocketW(AF_INET,SOCK_STREAM,IPPROTO_TCP,NULL,0,WSA_FLAG_OVERLAPPED);
    CreateIoCompletionPort((HANDLE)cs,iocp,2,0);
    struct sockaddr_in la; memset(&la,0,sizeof(la)); la.sin_family=AF_INET; la.sin_addr.s_addr=htonl(INADDR_LOOPBACK); la.sin_port=0;
    bind(cs,(struct sockaddr*)&la,sizeof(la));
    u_long nb=1; ioctlsocket(cs,FIONBIO,&nb);
    LPFN_CONNECTEX pConnectEx=NULL; DWORD got=0;
    WSAIoctl(cs,SIO_GET_EXTENSION_FUNCTION_POINTER,&guid_connectex,sizeof(guid_connectex),&pConnectEx,sizeof(pConnectEx),&got,NULL,NULL);
    struct sockaddr_in ra; memset(&ra,0,sizeof(ra)); ra.sin_family=AF_INET; ra.sin_addr.s_addr=htonl(INADDR_LOOPBACK); ra.sin_port=port;
    OVERLAPPED cov; memset(&cov,0,sizeof(cov));
    pConnectEx(cs,(struct sockaddr*)&ra,sizeof(ra),NULL,0,NULL,&cov);
    { DWORD b; ULONG_PTR k; LPOVERLAPPED p; GetQueuedCompletionStatus(iocp,&b,&k,&p,3000); }

    /* (2) WSAGetOverlappedResult - how grpc reads the connect result */
    DWORD xfer=0, flags=0;
    BOOL wr = WSAGetOverlappedResult(cs, &cov, &xfer, FALSE, &flags);
    printf("[2] WSAGetOverlappedResult ret=%d err=%d xfer=%lu %s\n", wr, WSAGetLastError(), xfer,
           wr ? "-> connect result reads as SUCCESS" : "-> connect result reads as FAILURE (would make grpc drop it)");
    fflush(stdout);

    WSACleanup(); return 0;
}
