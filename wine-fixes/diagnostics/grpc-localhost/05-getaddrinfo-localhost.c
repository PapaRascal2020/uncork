#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdio.h>
int main(void){
  WSADATA w; WSAStartup(MAKEWORD(2,2),&w);
  struct addrinfo hints, *res=NULL; memset(&hints,0,sizeof(hints));
  hints.ai_family=AF_UNSPEC; hints.ai_socktype=SOCK_STREAM;
  DWORD t0=GetTickCount();
  int r=getaddrinfo("localhost","50563",&hints,&res);
  DWORD dt=GetTickCount()-t0;
  printf("getaddrinfo(localhost) ret=%d in %lums\n", r, dt);
  if(r==0){ for(struct addrinfo*p=res;p;p=p->ai_next){ char b[64]; void*a = p->ai_family==AF_INET?(void*)&((struct sockaddr_in*)p->ai_addr)->sin_addr:(void*)&((struct sockaddr_in6*)p->ai_addr)->sin6_addr; inet_ntop(p->ai_family,a,b,sizeof(b)); printf("  -> family=%d %s\n", p->ai_family, b);} }
  else printf("  FAILED err=%d\n", WSAGetLastError());
  WSACleanup(); return 0;
}
