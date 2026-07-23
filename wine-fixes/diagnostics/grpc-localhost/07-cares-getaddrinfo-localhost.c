#include <winsock2.h>
#include <ws2tcpip.h>
#include <ares.h>
#include <windows.h>
#include <stdio.h>
static volatile int done=0;
static void cb(void *arg, int status, int timeouts, struct ares_addrinfo *result){
  DWORD *t0=(DWORD*)arg;
  printf("[cb] status=%d (%s) timeouts=%d after %lums\n", status, ares_strerror(status), timeouts, GetTickCount()-*t0);
  if(status==ARES_SUCCESS && result){
    for(struct ares_addrinfo_node *n=result->nodes;n;n=n->ai_next){
      char b[64]; void*a = n->ai_family==AF_INET?(void*)&((struct sockaddr_in*)n->ai_addr)->sin_addr:(void*)&((struct sockaddr_in6*)n->ai_addr)->sin6_addr;
      inet_ntop(n->ai_family,a,b,sizeof(b)); printf("   -> %s\n", b);
    }
  }
  if(result) ares_freeaddrinfo(result);
  done=1;
}
int main(void){
  WSADATA w; WSAStartup(MAKEWORD(2,2),&w);
  ares_library_init(ARES_LIB_INIT_ALL);
  ares_channel_t *ch=NULL;
  struct ares_options opt; int optmask=0;
  memset(&opt,0,sizeof(opt));
  if(ares_init_options(&ch,&opt,optmask)!=ARES_SUCCESS){printf("init failed\n");return 1;}
  // show what servers c-ares picked
  struct ares_addr_port_node *srv=NULL;
  if(ares_get_servers_ports(ch,&srv)==ARES_SUCCESS){
    printf("[cares] servers:\n");
    for(struct ares_addr_port_node *s=srv;s;s=s->next){ char b[64]; inet_ntop(s->family, s->family==AF_INET?(void*)&s->addr.addr4:(void*)&s->addr.addr6, b, sizeof(b)); printf("   %s:%d\n", b, s->udp_port);}
    ares_free_data(srv);
  }
  struct ares_addrinfo_hints h; memset(&h,0,sizeof(h)); h.ai_family=AF_UNSPEC; h.ai_flags=ARES_AI_NOSORT;
  DWORD t0=GetTickCount();
  printf("[main] ares_getaddrinfo(\"localhost\", \"55333\")...\n");
  ares_getaddrinfo(ch,"localhost","55333",&h,cb,&t0);
  // event loop
  for(int i=0;i<300 && !done;i++){
    fd_set rf,wf; FD_ZERO(&rf); FD_ZERO(&wf);
    int nfds=ares_fds(ch,&rf,&wf);
    if(nfds==0 && !done){ Sleep(20); ares_process(ch,&rf,&wf); continue; }
    struct timeval tv,*tvp; tvp=ares_timeout(ch,NULL,&tv);
    select(nfds,&rf,&wf,NULL,tvp);
    ares_process(ch,&rf,&wf);
  }
  if(!done) printf("[main] TIMED OUT (no callback in ~6s) -> c-ares stuck resolving localhost\n");
  ares_destroy(ch); ares_library_cleanup(); WSACleanup();
  return 0;
}
