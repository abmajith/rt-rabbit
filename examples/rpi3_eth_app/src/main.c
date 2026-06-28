#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/net/net_if.h>
#include <zephyr/net/net_ip.h>

LOG_MODULE_REGISTER(rpi3_boot, LOG_LEVEL_INF);

void main(void)
{
    LOG_INF("------------------------------------------------");
    LOG_INF("Zephyr RTOS Booted Successfully on QEMU!");
    LOG_INF("------------------------------------------------");

    /* Wait a moment for the virtual hardware driver to settle */
    k_sleep(K_MSEC(500));

    struct net_if *iface = net_if_get_default();
    
    if (iface) {
        struct in_addr local_addr;
        struct in_addr netmask;
        struct net_if_addr *ifaddr;

        /* 1. Parse and assign the static IP address */
        if (net_addr_pton(AF_INET, "192.168.192.2", &local_addr) == 0) {
            ifaddr = net_if_ipv4_addr_add(iface, &local_addr, NET_ADDR_MANUAL, 0);
            if (ifaddr) {
                LOG_INF("Static IP Assigned Successfully: 192.168.192.2");
            } else {
                LOG_ERR("Failed to assign static IP address slot!");
            }
        }

        /* 2. Parse and assign the Netmask (255.255.255.0 / Subnet /24) */
        if (net_addr_pton(AF_INET, "255.255.255.0", &netmask) == 0) {
            if (net_if_ipv4_set_netmask_by_addr(iface, &local_addr, &netmask)) {
                LOG_INF("Netmask Set Successfully: 255.255.255.0");
            } else {
                LOG_ERR("Failed to set netmask!");
            }
        }

        /* 3. Explicitly administrative up-state shift */
        net_if_up(iface);
        LOG_INF("Network interface explicitly brought UP.");

    } else {
        LOG_ERR("No default network interface found!");
    }

    while (1) {
        LOG_INF("Alive and waiting for network steps...");
        k_sleep(K_SECONDS(5));
    }
}