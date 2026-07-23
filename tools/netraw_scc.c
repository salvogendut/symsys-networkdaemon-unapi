#include <network.h>
#include <stdlib.h>
#include <symbos.h>

extern char _netmsg[14];
extern unsigned char Net_Command(void);

static char numbuf[8];

static void pnum(int value) {
    itoa(value, numbuf, 10);
    Shell_Print(numbuf);
}

static void pip(char *ip) {
    pnum((unsigned char)ip[0]);
    Shell_Print(".");
    pnum((unsigned char)ip[1]);
    Shell_Print(".");
    pnum((unsigned char)ip[2]);
    Shell_Print(".");
    pnum((unsigned char)ip[3]);
}

static int octet(char **pp) {
    char *p = *pp;
    int value = 0;
    int digits = 0;
    while (*p >= '0' && *p <= '9') {
        value = value * 10 + (*p - '0');
        if (value > 255) return -1;
        ++p;
        ++digits;
    }
    if (!digits) return -1;
    *pp = p;
    return value;
}

static int parse_ip(char *text, char *ip) {
    int i, value;
    char *p = text;
    for (i = 0; i < 4; ++i) {
        value = octet(&p);
        if (value < 0) return -1;
        ip[i] = value;
        if (i < 3) {
            if (*p != '.') return -1;
            ++p;
        }
    }
    return *p ? -1 : 0;
}

static void print_result(char *prefix, unsigned char result) {
    Shell_Print(prefix);
    Shell_Print(" res=");
    pnum(result);
    Shell_Print(" msg=");
    pnum((unsigned char)_netmsg[0]);
    Shell_Print(" cf=");
    pnum((unsigned char)_netmsg[2] & 1);
    Shell_Print(" a=");
    pnum((unsigned char)_netmsg[3]);
    Shell_Print(" st=");
    pnum((unsigned char)_netmsg[8] & 31);
    Shell_Print(" bytes=");
    pnum(*(unsigned short *)(_netmsg + 4));
    Shell_Print("\r\n");
}

int main(int argc, char **argv) {
    char ip[4];
    int port;
    int i;
    signed char socket;

    Shell_Print("RAW TCP test\r\n");
    if (Net_Init() < 0) {
        Shell_Print("Net_Init FAIL\r\n");
        return 1;
    }

    if (argc > 1) {
        if (parse_ip(argv[1], ip) < 0) {
            Shell_Print("Bad IP\r\n");
            return 1;
        }
    } else {
        ip[0] = 1; ip[1] = 1; ip[2] = 1; ip[3] = 1;
    }
    port = argc > 2 ? atoi(argv[2]) : 80;

    Shell_Print("open ");
    pip(ip);
    Shell_Print(":");
    pnum(port);
    Shell_Print("\r\n");

    _netmsg[0] = 16;
    _netmsg[3] = 0;
    *(unsigned short *)(_netmsg + 6) = port;
    *(unsigned short *)(_netmsg + 8) = -1;
    _netmsg[10] = ip[0];
    _netmsg[11] = ip[1];
    _netmsg[12] = ip[2];
    _netmsg[13] = ip[3];
    if (Net_Command()) {
        print_result("open", _neterr);
        return 1;
    }
    socket = _netmsg[3];
    print_result("open", 0);

    for (i = 0; i < 30; ++i) {
        _netmsg[0] = 18;
        _netmsg[3] = socket;
        print_result("stat", Net_Command());
        Idle();
    }

    _netmsg[0] = 23;
    _netmsg[3] = socket;
    print_result("disc", Net_Command());
    return 0;
}
