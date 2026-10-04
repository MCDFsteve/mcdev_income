#define MCDEV_NETWORK_TEST 1
#include "ipv6_scope.c"
#include <assert.h>
#include <stdio.h>
#include <unistd.h>

int main(void) {
  struct sockaddr_in6 target = {.sin6_len = sizeof(target),
                               .sin6_family = AF_INET6,
                               .sin6_port = htons(19133)};
  target.sin6_addr.s6_addr[0] = 0xff;
  target.sin6_addr.s6_addr[1] = 2;
  target.sin6_addr.s6_addr[15] = 1;
  struct msghdr message = {.msg_name = &target, .msg_namelen = sizeof(target)};
  assert(discovery_address(&message));
  target.sin6_scope_id = 7;
  assert(!discovery_address(&message));
  target.sin6_scope_id = 0;
  target.sin6_port = htons(19132);
  assert(!discovery_address(&message));
  target.sin6_port = htons(19133);
  target.sin6_addr.s6_addr[15] = 2;
  assert(!discovery_address(&message));
  target.sin6_addr.s6_addr[15] = 1;
  message.msg_controllen = 1;
  assert(!discovery_address(&message));
  message.msg_controllen = 0;
  message.msg_namelen--;
  assert(!discovery_address(&message));
  message.msg_namelen++;
  assert(!discovery_address(NULL));

  struct sockaddr_in6 address = {.sin6_family = AF_INET6};
  address.sin6_addr.s6_addr[0] = 0xfe;
  address.sin6_addr.s6_addr[1] = 0x80;
  struct ifaddrs second = {.ifa_name = "en7", .ifa_flags = IFF_UP | IFF_MULTICAST,
                          .ifa_addr = (void *)&address};
  struct ifaddrs first = {.ifa_next = &second, .ifa_name = "en4",
                         .ifa_flags = IFF_UP | IFF_MULTICAST,
                         .ifa_addr = (void *)&address};
  assert(!strcmp(choose_interface(&first, NULL, "en7"), "en7"));
  assert(!strcmp(choose_interface(&first, NULL, "utun0"), "en4"));
  first.ifa_flags |= IFF_POINTOPOINT;
  assert(!strcmp(choose_interface(&first, NULL, "en4"), "en7"));
  second.ifa_flags |= IFF_LOOPBACK;
  assert(!choose_interface(&first, NULL, NULL));
  first.ifa_flags = IFF_MULTICAST;
  second.ifa_flags = IFF_UP | IFF_MULTICAST;
  assert(!strcmp(choose_interface(&first, NULL, "en4"), "en7"));
  assert(!strcmp(choose_interface(&first, &address, "en4"), "en7"));
  assert(!choose_interface(NULL, NULL, "en0"));

  /* An explicitly selected socket interface wins over automatic LAN choice. */
  int ipv6 = socket(AF_INET6, SOCK_DGRAM, 0);
  assert(ipv6 >= 0);
  unsigned int loopback = if_nametoindex("lo0");
  assert(loopback);
  assert(!setsockopt(ipv6, IPPROTO_IPV6, IPV6_MULTICAST_IF, &loopback, sizeof(loopback)));
  assert(socket_scope(ipv6) == loopback);
  close(ipv6);

  /* Unrelated loopback UDP still transmits its original payload and errno. */
  int receiver = socket(AF_INET, SOCK_DGRAM, 0);
  int sender = socket(AF_INET, SOCK_DGRAM, 0);
  assert(receiver >= 0 && sender >= 0);
  struct sockaddr_in local = {.sin_len = sizeof(local), .sin_family = AF_INET,
                             .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
  assert(!bind(receiver, (void *)&local, sizeof(local)));
  socklen_t length = sizeof(local);
  assert(!getsockname(receiver, (void *)&local, &length));
  char payload[] = "unchanged";
  struct iovec buffer = {.iov_base = payload, .iov_len = sizeof(payload)};
  message = (struct msghdr){.msg_name = &local, .msg_namelen = sizeof(local),
                           .msg_iov = &buffer, .msg_iovlen = 1};
  assert(scoped_sendmsg(sender, &message, 0) == sizeof(payload));
  char received[sizeof(payload)] = {0};
  assert(recv(receiver, received, sizeof(received), 0) == sizeof(payload));
  assert(!memcmp(received, payload, sizeof(payload)));
  assert(scoped_sendmsg(-1, &message, 0) == -1 && errno == EBADF);
  close(receiver);
  close(sender);
  puts("IPv6 discovery scope and UDP passthrough checks passed");
}
