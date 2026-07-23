/* Tests Wine's GetAddrInfoExW - SYNC then ASYNC(overlapped) - for "localhost".
 * Modern gRPC's Windows EventEngine DNS resolver uses the async form; if Wine
 * never completes the overlapped op, the gRPC channel hangs at "resolving". */
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdio.h>
static volatile int g_done=0; static DWORD g_t0;
static void CALLBACK compRoutine(DWORD err, DWORD bytes, LPWSAOVERLAPPED ov){
  printf("[async cb] err=%lu after %lums\n", err, GetTickCount()-g_t0); g_done=1;
}
int main(void){
  WSADATA w; WSAStartup(MAKEWORD(2,2),&w);
  ADDRINFOEXW hints; memset(&hints,0,sizeof(hints)); hints.ai_family=AF_UNSPEC; hints.ai_socktype=SOCK_STREAM;
  PADDRINFOEXW res=NULL;
  /* SYNC */
  DWORD t0=GetTickCount();
  int r=GetAddrInfoExW(L"localhost",L"55333",NS_ALL,NULL,&hints,&res,NULL,NULL,NULL,NULL);
  printf("[sync ] GetAddrInfoExW ret=%d err=%d after %lums\n", r, WSAGetLastError(), GetTickCount()-t0);
  if(res){ FreeAddrInfoExW(res); res=NULL; }
  /* ASYNC via completion routine */
  WSAOVERLAPPED ov; memset(&ov,0,sizeof(ov));
  HANDLE cancel=NULL; g_t0=GetTickCount();
  int ar=GetAddrInfoExW(L"localhost",L"55333",NS_ALL,NULL,&hints,&res,NULL,&ov,compRoutine,&cancel);
  printf("[async] GetAddrInfoExW ret=%d err=%d %s\n", ar, WSAGetLastError(),
         ar==WSA_IO_PENDING||WSAGetLastError()==WSA_IO_PENDING?"(pending - waiting for completion)":"(immediate)");
  /* pump alertable waits for the completion routine */
  for(int i=0;i<200 && !g_done;i++){ SleepEx(20, TRUE); }
  if(!g_done) printf("[async] *** NO COMPLETION in ~4s -> Wine async GetAddrInfoExW never completes (THE BUG) ***\n");
  WSACleanup(); return 0;
}
