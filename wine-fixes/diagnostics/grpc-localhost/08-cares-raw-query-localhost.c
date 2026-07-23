/* Mimics OLD gRPC: raw ares_query for A/AAAA of "localhost" (NO hosts-file consult). */
#include <winsock2.h>
#include <ws2tcpip.h>
#include <ares.h>
#include <windows.h>
#include <stdio.h>
static volatile int done=0; static DWORD t0;
static void qcb(void *arg, int status, int timeouts, unsigned char *abuf, int alen){
  printf("[query %s] status=%d (%s) timeouts=%d after %lums alen=%d\n",
         (char*)arg, status, ares_strerror(status), timeouts, GetTickCount()-t0, alen);
  done++;
}
int main(void){
  WSADATA w; WSAStartup(MAKEWORD(2,2),&w);
  ares_library_init(ARES_LIB_INIT_ALL);
  ares_channel_t *ch=NULL; struct ares_options opt; memset(&opt,0,sizeof(opt));
  ares_init_options(&ch,&opt,0);
  t0=GetTickCount();
  printf("[main] ares_query A + AAAA for \"localhost\" (raw DNS, old-gRPC style)...\n");
  ares_query(ch,"localhost",1,1,qcb,"A");
  ares_query(ch,"localhost",1,28,qcb,"AAAA");
  for(int i=0;i<400 && done<2;i++){
    fd_set rf,wf; FD_ZERO(&rf); FD_ZERO(&wf);
    int nfds=ares_fds(ch,&rf,&wf);
    if(nfds==0 && done<2){ Sleep(20); continue; }
    struct timeval tv,*tvp; tvp=ares_timeout(ch,NULL,&tv);
    select(nfds,&rf,&wf,NULL,tvp);
    ares_process(ch,&rf,&wf);
  }
  if(done<2) printf("[main] TIMED OUT (%d/2 answered in ~8s) -> raw-DNS localhost HANGS (this is EA's failure)\n", done);
  ares_destroy(ch); ares_library_cleanup(); WSACleanup(); return 0;
}
