#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <windows.h>
#include <stdio.h>
int main(void){
  WSADATA w; WSAStartup(MAKEWORD(2,2),&w);
  // GetNetworkParams DNS list
  FIXED_INFO fi; ULONG n=sizeof(fi);
  FIXED_INFO *p=(FIXED_INFO*)malloc(sizeof(FIXED_INFO));
  n=sizeof(FIXED_INFO);
  if(GetNetworkParams(p,&n)==ERROR_BUFFER_OVERFLOW){ p=(FIXED_INFO*)realloc(p,n); }
  if(GetNetworkParams(p,&n)==NO_ERROR){
    printf("GetNetworkParams DNS servers:\n");
    IP_ADDR_STRING *d=&p->DnsServerList;
    int any=0;
    while(d){ if(d->IpAddress.String[0]){ printf("  %s\n", d->IpAddress.String); any=1;} d=d->Next; }
    if(!any) printf("  (NONE)\n");
  } else printf("GetNetworkParams failed\n");
  // GetAdaptersAddresses DNS list
  ULONG sz=15000; IP_ADAPTER_ADDRESSES *aa=(IP_ADAPTER_ADDRESSES*)malloc(sz);
  if(GetAdaptersAddresses(AF_UNSPEC, GAA_FLAG_INCLUDE_ALL_INTERFACES, NULL, aa, &sz)==NO_ERROR){
    printf("GetAdaptersAddresses DNS servers:\n"); int any=0;
    for(IP_ADAPTER_ADDRESSES*a=aa;a;a=a->Next){
      for(IP_ADAPTER_DNS_SERVER_ADDRESS*ds=a->FirstDnsServerAddress;ds;ds=ds->Next){
        char b[64]; DWORD bl=sizeof(b);
        WSAAddressToStringA(ds->Address.lpSockaddr, ds->Address.iSockaddrLength, NULL, b, &bl);
        printf("  [%ls] %s\n", a->FriendlyName, b); any=1;
      }
    }
    if(!any) printf("  (NONE)\n");
  } else printf("GetAdaptersAddresses failed\n");
  WSACleanup(); return 0;
}
