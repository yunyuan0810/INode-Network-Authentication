// less than 320k

#include "auth.h"
#include "crypto/crypto.h"
#include "packet/packet.h"
#include "packet/send.h"
#include "utils/config.h"
#include "utils/device.h"
#include "utils/log.h"

#include <pcap/pcap.h>
#include <signal.h>

// Set by the signal handler; checked in the main loop.
// volatile sig_atomic_t is the only type safe to write from a signal handler.
static volatile sig_atomic_t g_exit_flag = 0;

static void sig_handler(int sig) {
  (void)sig;
  g_exit_flag = 1;
}

static void do_exit(void) {
  if (g_device.handle) {
    send_signoff_packet();
    pcap_close(g_device.handle);
  }
  log_info("bye!", NULL);
  exit(EXIT_SUCCESS);
}

int main(int argc, char *argv[]) {
  if (argc < 2) {
    log_info("Usage: zzz [path_to_config]", NULL);
    exit(EXIT_FAILURE);
  }

  signal(SIGINT, sig_handler);
  signal(SIGTERM, sig_handler);
  config_init(argv[1]);
  device_init(g_config.device);
  packet_init_default();
  crypto_init();

  auth_handshake();
  int ret;
  while ((ret = auth_loop()) == 0) {
    if (g_exit_flag)
      do_exit();
  }
  do_exit();

  return 0;
}
