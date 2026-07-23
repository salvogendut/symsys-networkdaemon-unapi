#include <network.h>
#include <stdlib.h>
#include <string.h>
#include <symbos.h>

static signed char socket = -1;
static char request[] =
    "GET / HTTP/1.0\r\n"
    "Host: nettest\r\n"
    "Connection: close\r\n"
    "\r\n";
static char numbuf[8];
extern unsigned short _nettimeout;

static void print_num(int value) {
    itoa(value, numbuf, 10);
    Shell_Print(numbuf);
}

static void print_neterr(void) {
    Shell_Print("neterr=");
    print_num((int)_neterr);
    Shell_Print("\r\n");
}

static void print_ip(char *ip) {
    print_num((unsigned char)ip[0]);
    Shell_Print(".");
    print_num((unsigned char)ip[1]);
    Shell_Print(".");
    print_num((unsigned char)ip[2]);
    Shell_Print(".");
    print_num((unsigned char)ip[3]);
}

static int parse_ip_octet(char **pp) {
    int value;
    int digits;
    char *p;

    value = 0;
    digits = 0;
    p = *pp;
    while (*p >= '0' && *p <= '9') {
        value = value * 10 + (*p - '0');
        if (value > 255)
            return -1;
        ++p;
        ++digits;
    }
    if (!digits)
        return -1;
    *pp = p;
    return value;
}

static int parse_ip(char *text, char *ip) {
    int i;
    int value;
    char *p;

    p = text;
    for (i = 0; i < 4; ++i) {
        value = parse_ip_octet(&p);
        if (value < 0)
            return -1;
        ip[i] = value;
        if (i < 3) {
            if (*p != '.')
                return -1;
            ++p;
        }
    }
    return *p ? -1 : 0;
}

int main(int argc, char **argv) {
    char ip[4];
    NetStat st;
    char *host;
    int port;

    Shell_Print("SCC TCP test\r\n");
    _nettimeout = 500;

    Shell_Print("Net_Init... ");
    if (Net_Init() < 0) {
        Shell_Print("FAIL ");
        print_neterr();
        return 1;
    }
    Shell_Print("OK pid=");
    print_num((int)_netpid);
    Shell_Print("\r\n");

    host = "1.1.1.1";
    port = 80;
    if (argc > 1)
        host = argv[1];
    if (argc > 2)
        port = atoi(argv[2]);

    if (parse_ip(host, ip) < 0) {
        Shell_Print("DNS_Resolve ");
        Shell_Print(host);
        Shell_Print("... ");
        if (DNS_Resolve(_symbank, host, ip) < 0) {
            Shell_Print("FAIL ");
            print_neterr();
            return 1;
        }
        Shell_Print("OK ");
        print_ip(ip);
        Shell_Print("\r\n");
    }

    Shell_Print("TCP_OpenClient ");
    print_ip(ip);
    Shell_Print(":");
    print_num(port);
    Shell_Print("...\r\n");
    socket = TCP_OpenClient(ip, -1, port);
    if (socket < 0) {
        Shell_Print("TCP_OpenClient FAIL ");
        print_neterr();
        return 1;
    }
    Shell_Print("socket=");
    print_num((int)socket);
    Shell_Print("\r\n");

    Shell_Print("TCP_Status... ");
    if (TCP_Status((unsigned char)socket, &st) < 0) {
        Shell_Print("FAIL ");
        print_neterr();
        TCP_Close((unsigned char)socket);
        return 1;
    }
    Shell_Print("status=");
    print_num((int)st.status);
    Shell_Print(" rec=");
    print_num((int)st.bytesrec);
    Shell_Print("\r\n");

    Shell_Print("TCP_Send ");
    print_num((int)strlen(request));
    Shell_Print(" bytes... ");
    if (TCP_Send((unsigned char)socket, _symbank, request, strlen(request)) < 0) {
        Shell_Print("FAIL ");
        print_neterr();
        TCP_Close((unsigned char)socket);
        return 1;
    }
    Shell_Print("OK\r\n");

    Shell_Print("TCP_Disconnect... ");
    if (TCP_Disconnect((unsigned char)socket) < 0) {
        Shell_Print("FAIL ");
        print_neterr();
        TCP_Close((unsigned char)socket);
        return 1;
    }
    Shell_Print("OK\r\n");

    Shell_Print("Done\r\n");
    return 0;
}
