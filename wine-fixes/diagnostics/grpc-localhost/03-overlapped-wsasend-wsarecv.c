/* cxtest3.c - full overlapped bidirectional data over localhost via IOCP,
 * the last piece to clear (or implicate) Wine's winsock for gRPC's HTTP/2.
 * Client ConnectEx -> WSASend(preface) ; server AcceptEx -> WSARecv -> WSASend(reply).
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

    SOCKET ls = WSASocketW(AF_INET,SOCK_STREAM,IPPROTO_TCP,NULL,0,WSA_FLAG_OVERLAPPED);
    struct sockaddr_in a; int len=sizeof(a); memset(&a,0,sizeof(a));
    a.sin_family=AF_INET; a.sin_addr.s_addr=htonl(INADDR_LOOPBACK); a.sin_port=0;
    bind(ls,(struct sockaddr*)&a,sizeof(a)); listen(ls,8);
    getsockname(ls,(struct sockaddr*)&a,&len); u_short port=a.sin_port;
    CreateIoCompletionPort((HANDLE)ls,iocp,1,0);
    SOCKET as = WSASocketW(AF_INET,SOCK_STREAM,IPPROTO_TCP,NULL,0,WSA_FLAG_OVERLAPPED);
    LPFN_ACCEPTEX pAcceptEx=NULL; DWORD got=0;
    WSAIoctl(ls,SIO_GET_EXTENSION_FUNCTION_POINTER,&guid_acceptex,sizeof(guid_acceptex),&pAcceptEx,sizeof(pAcceptEx),&got,NULL,NULL);
    char abuf[2*(sizeof(struct sockaddr_in)+16)]; OVERLAPPED aov; memset(&aov,0,sizeof(aov)); DWORD ab=0;
    pAcceptEx(ls,as,abuf,0,sizeof(struct sockaddr_in)+16,sizeof(struct sockaddr_in)+16,&ab,&aov);

    SOCKET cs=WSASocketW(AF_INET,SOCK_STREAM,IPPROTO_TCP,NULL,0,WSA_FLAG_OVERLAPPED);
    CreateIoCompletionPort((HANDLE)cs,iocp,2,0);
    struct sockaddr_in la; memset(&la,0,sizeof(la)); la.sin_family=AF_INET; la.sin_addr.s_addr=htonl(INADDR_LOOPBACK); la.sin_port=0;
    bind(cs,(struct sockaddr*)&la,sizeof(la));
    u_long nb=1; ioctlsocket(cs,FIONBIO,&nb);
    LPFN_CONNECTEX pConnectEx=NULL;
    WSAIoctl(cs,SIO_GET_EXTENSION_FUNCTION_POINTER,&guid_connectex,sizeof(guid_connectex),&pConnectEx,sizeof(pConnectEx),&got,NULL,NULL);
    struct sockaddr_in ra; memset(&ra,0,sizeof(ra)); ra.sin_family=AF_INET; ra.sin_addr.s_addr=htonl(INADDR_LOOPBACK); ra.sin_port=port;
    OVERLAPPED cov; memset(&cov,0,sizeof(cov));
    pConnectEx(cs,(struct sockaddr*)&ra,sizeof(ra),NULL,0,NULL,&cov);

    /* wait connect + accept */
    int ready=0;
    while (ready<2){ DWORD b; ULONG_PTR k; LPOVERLAPPED p; if(!GetQueuedCompletionStatus(iocp,&b,&k,&p,3000)&&!p){printf("[fail] no conn/acc completion\n");return 1;} if(k==1||k==2)ready++; }
    setsockopt(cs,SOL_SOCKET,SO_UPDATE_CONNECT_CONTEXT,NULL,0);
    setsockopt(as,SOL_SOCKET,SO_UPDATE_ACCEPT_CONTEXT,(char*)&ls,sizeof(ls));
    CreateIoCompletionPort((HANDLE)as,iocp,3,0);
    printf("[ok] connected+accepted, now overlapped data...\n"); fflush(stdout);

    /* server posts overlapped WSARecv */
    char rbuf[64]; WSABUF rb={sizeof(rbuf),rbuf}; DWORD rflags=0; OVERLAPPED rov; memset(&rov,0,sizeof(rov));
    int rr=WSARecv(as,&rb,1,NULL,&rflags,&rov,NULL);
    printf("[srv] WSARecv posted ret=%d err=%d\n",rr,WSAGetLastError());
    /* client sends overlapped preface */
    char pre[]="PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"; WSABUF sb={sizeof(pre)-1,pre}; OVERLAPPED sov; memset(&sov,0,sizeof(sov));
    int sr=WSASend(cs,&sb,1,NULL,0,&sov,NULL);
    printf("[cli] WSASend posted ret=%d err=%d\n",sr,WSAGetLastError()); fflush(stdout);

    int done_send=0, done_recv=0;
    for(int i=0;i<2;i++){ DWORD b; ULONG_PTR k; LPOVERLAPPED p;
        if(!GetQueuedCompletionStatus(iocp,&b,&k,&p,3000)&&!p){printf("[fail] no data completion (send=%d recv=%d)\n",done_send,done_recv);break;}
        printf("[iocp] data completion key=%llu bytes=%lu\n",(unsigned long long)k,b);
        if(k==2)done_send=1; if(k==3){done_recv=1; if(b>0){rbuf[b<64?b:63]=0;}}
        fflush(stdout);
    }
    printf("[result] overlapped WSASend completed: %s\n", done_send?"YES":"NO");
    printf("[result] overlapped WSARecv completed: %s (%s)\n", done_recv?"YES":"NO", done_recv?"server received client preface":"");
    fflush(stdout);
    WSACleanup(); return 0;
}
