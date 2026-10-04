#include <SystemConfiguration/SystemConfiguration.h>
#include <errno.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>

/* Wine's RakNet sendto(ff02::1:19133) has no IPv6 zone. On affected macOS
 * hosts it remains pending in the content filter, blocking the game thread.
 * Supply a LAN interface for this discovery packet, preserving explicit
 * routing choices and every other sendmsg call. */
static int discovery_address(const struct msghdr *message) {
  static const unsigned char all_nodes[16] = {0xff, 2, 0, 0, 0, 0, 0, 0,
                                             0, 0, 0, 0, 0, 0, 0, 1};
  if (!message || !message->msg_name ||
      message->msg_namelen != sizeof(struct sockaddr_in6) ||
      message->msg_controllen) return 0;
  const struct sockaddr_in6 *address = message->msg_name;
  return address->sin6_family == AF_INET6 && !address->sin6_scope_id &&
         ntohs(address->sin6_port) == 19133 &&
         !memcmp(&address->sin6_addr, all_nodes, sizeof(all_nodes));
}

static int lan_interface(const struct ifaddrs *entry) {
  if (!entry->ifa_addr || entry->ifa_addr->sa_family != AF_INET6 ||
      (entry->ifa_flags & (IFF_UP | IFF_MULTICAST)) != (IFF_UP | IFF_MULTICAST) ||
      (entry->ifa_flags & (IFF_LOOPBACK | IFF_POINTOPOINT))) return 0;
  const struct sockaddr_in6 *address = (const void *)entry->ifa_addr;
  return IN6_IS_ADDR_LINKLOCAL(&address->sin6_addr);
}

static const char *choose_interface(const struct ifaddrs *list,
                                   const struct sockaddr_in6 *bound,
                                   const char *primary) {
  const char *fallback = NULL;
  for (const struct ifaddrs *entry = list; entry; entry = entry->ifa_next) {
    if (!entry->ifa_addr || entry->ifa_addr->sa_family != AF_INET6 ||
        !(entry->ifa_flags & IFF_UP)) continue;
    const struct sockaddr_in6 *address = (const void *)entry->ifa_addr;
    if (bound && !IN6_IS_ADDR_UNSPECIFIED(&bound->sin6_addr) &&
        !memcmp(&bound->sin6_addr, &address->sin6_addr, sizeof(bound->sin6_addr)))
      return entry->ifa_name;
    if (!lan_interface(entry)) continue;
    if (primary && !strcmp(primary, entry->ifa_name)) fallback = primary;
    else if (!fallback) fallback = entry->ifa_name;
  }
  return fallback;
}

static void primary_interface(const char *key, char *name, size_t length) {
  CFStringRef cf_key = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
  if (!cf_key) return;
  CFPropertyListRef value = SCDynamicStoreCopyValue(NULL, cf_key);
  CFRelease(cf_key);
  if (!value) return;
  if (CFGetTypeID(value) == CFDictionaryGetTypeID()) {
    CFTypeRef interface = CFDictionaryGetValue(value, CFSTR("PrimaryInterface"));
    if (interface && CFGetTypeID(interface) == CFStringGetTypeID())
      CFStringGetCString(interface, name, length, kCFStringEncodingUTF8);
  }
  CFRelease(value);
}

static unsigned int socket_scope(int fd) {
  unsigned int index = 0;
  socklen_t length = sizeof(index);
  if (!getsockopt(fd, IPPROTO_IPV6, IPV6_MULTICAST_IF, &index, &length) && index)
    return index;
  struct sockaddr_in6 bound = {0};
  length = sizeof(bound);
  if (getsockname(fd, (struct sockaddr *)&bound, &length) ||
      bound.sin6_family != AF_INET6) memset(&bound, 0, sizeof(bound));
  if (bound.sin6_scope_id) return bound.sin6_scope_id;
  struct ifaddrs *interfaces = NULL;
  if (getifaddrs(&interfaces)) return 0;
  char primary[IF_NAMESIZE] = {0};
  primary_interface("State:/Network/Global/IPv6", primary, sizeof(primary));
  if (!primary[0])
    primary_interface("State:/Network/Global/IPv4", primary, sizeof(primary));
  const char *name = choose_interface(interfaces, &bound, primary);
  if (name) index = if_nametoindex(name);
  freeifaddrs(interfaces);
  return index;
}

static ssize_t scoped_sendmsg(int fd, const struct msghdr *message, int flags) {
  if (discovery_address(message)) {
    int saved_errno = errno;
    unsigned int index = socket_scope(fd);
    errno = saved_errno;
    if (index) {
      struct sockaddr_in6 address = *(const struct sockaddr_in6 *)message->msg_name;
      struct msghdr scoped = *message;
      address.sin6_scope_id = index;
      scoped.msg_name = &address;
      return sendmsg(fd, &scoped, flags);
    }
  }
  return sendmsg(fd, message, flags);
}

#ifndef MCDEV_NETWORK_TEST
__attribute__((used)) static const struct {
  const void *replacement;
  const void *original;
} interpose __attribute__((section("__DATA,__interpose"))) = {
    (const void *)scoped_sendmsg, (const void *)sendmsg};
#endif
