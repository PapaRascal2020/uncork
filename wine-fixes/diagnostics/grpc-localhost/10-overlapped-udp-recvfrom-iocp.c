#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdio.h>
int main(void){
  WSADATA w; WSAStartup(MAKEWORD(2,2),&w);
  HANDLE iocp=CreateIoCompletionPort(INVALID_HANDLE_VALUE,NULL,0,0);
  SOCKET s=WSASocketW(AF_INET,SOCK_DGRAM,IPPROTO_UDP,NULL,0,WSA_FLAG_OVERLAPPED);
  struct sockaddr_in a; int len=sizeof(a); memset(&a,0,sizeof(a));
  a.sin_family=AF_INET; a.sin_addr.s_addr=htonl(INADDR_LOOPBACK); a.sin_port=0;
  bind(s,(struct sockaddr*)&a,sizeof(a)); getsockname(s,(struct sockaddr*)&a,&len);
  CreateIoCompletionPort((HANDLE)s,iocp,0xDEAD,0);
  u_long nb=1; ioctlsocket(s,FIONBIO,&nb);
  char buf[512]; WSABUF rb={sizeof(buf),buf}; DWORD flags=0; OVERLAPPED ov; memset(&ov,0,sizeof(ov));
  struct sockaddr_in from; int fromlen=sizeof(from);
  int rr=WSARecvFrom(s,&rb,1,NULL,&flags,(struct sockaddr*)&from,&fromlen,&ov,NULL);
  printf("[recvfrom] posted ret=%d err=%d\n", rr, WSAGetLastError());
  SOCKET c=socket(AF_INET,SOCK_DGRAM,IPPROTO_UDP);
  sendto(c,"DNSRESP",7,0,(struct sockaddr*)&a,sizeof(a));
  printf("[sender] sent 7 bytes\n");
  DWORD b; ULONG_PTR k; LPOVERLAPPED p;
  BOOL cok=GetQueuedCompletionStatus(iocp,&b,&k,&p,3000);
  if(cok && p==&ov){ buf[b]=0; printf("[iocp] recvfrom completed bytes=%lu data=[%s] -> WORKS\n", b, buf); }
  else if(!cok && !p) printf("[iocp] TIMEOUT -> overlapped UDP WSARecvFrom via IOCP is BROKEN under Wine\n");
  else printf("[iocp] unexpected cok=%d bytes=%lu p=%p\n", cok, b, (void*)p);
  WSACleanup(); return 0;
}
