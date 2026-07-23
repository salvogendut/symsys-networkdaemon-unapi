#include <network.h>
#include <stdlib.h>
#include <string.h>
#include <symbos.h>

#define STARTUP_TIMEOUT 1500
#define PROVIDER_WARMUP 1000
#define DNS_RETRY_TIMEOUT 3000
#define NETWORK_TIMEOUT 1000
#define RESPONSE_SIZE 1024

#ifdef PROBE_LOCAL
#ifndef PROBE_PORT
#define PROBE_PORT 8080
#endif
#define PROBE_HOST_HEADER "localhost"
#else
static char host[] = "example.com";
#ifndef PROBE_PORT
#define PROBE_PORT 80
#endif
#define PROBE_HOST_HEADER "example.com"
#endif
static char request[] =
    "GET /__symbos_unapi_probe__ HTTP/1.0\r\n"
    "Host: " PROBE_HOST_HEADER "\r\n"
    "Connection: close\r\n"
    "\r\n";
static char log_path[] = "A:/SYMBOS/UNAPITST.LOG";
static char response[RESPONSE_SIZE];
static char numbuf[8];
static char result_line[64];
static char detail_line[64];
static char *failure_step;
static unsigned char failure_error;
static signed char probe_socket = -1;
static unsigned short received_total;

extern unsigned short _nettimeout;

static void print_num(int value) {
    itoa(value, numbuf, 10);
    Shell_Print(numbuf);
}

static void print_error(void) {
    Shell_Print("FAIL neterr=");
    print_num((unsigned char)_neterr);
    Shell_Print("\r\n");
}

static void write_log_line(unsigned char fd, char *line) {
    File_Write(fd, _symbank, line, strlen(line));
    File_Write(fd, _symbank, "\r\n", 2);
}

static void write_result_log(void) {
    unsigned char fd;

    fd = File_New(_symbank, log_path, 0);
    if (fd > 7)
        return;
    write_log_line(fd, "UNAPI network probe");
    write_log_line(fd, result_line);
    write_log_line(fd, detail_line);
    File_Close(fd);
}

static void write_progress(char *step) {
    unsigned char fd;

    fd = File_New(_symbank, log_path, 0);
    if (fd > 7)
        return;
    write_log_line(fd, "UNAPI network probe");
    write_log_line(fd, step);
    File_Close(fd);
}

static void show_result(char *summary) {
    strcpy(result_line, "Result: ");
    strcat(result_line, summary);
    if (failure_step) {
        strcpy(detail_line, "Step: ");
        strcat(detail_line, failure_step);
        if (probe_socket >= 0) {
            strcat(detail_line, " s=");
            itoa(probe_socket, numbuf, 10);
            strcat(detail_line, numbuf);
        }
        strcat(detail_line, " error ");
        itoa(failure_error, numbuf, 10);
        strcat(detail_line, numbuf);
    } else {
        strcpy(detail_line, "Received ");
        itoa(received_total, numbuf, 10);
        strcat(detail_line, numbuf);
        strcat(detail_line, " bytes");
    }
    write_result_log();
    MsgBox("UNAPI network probe", result_line, detail_line,
           COLOR_BLACK, BUTTON_OK, 0, 0, 0);
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

static int network_when_ready(char *ip) {
    unsigned short started;

    started = Sys_Counter16();
    while (Net_Init() != 0) {
        if ((unsigned short)(Sys_Counter16() - started) >= STARTUP_TIMEOUT)
            return -1;
        Idle();
    }

#ifdef PROBE_LOCAL
    ip[0] = 127;
    ip[1] = 0;
    ip[2] = 0;
    ip[3] = 1;
    return 0;
#else
    started = Sys_Counter16();
    while ((unsigned short)(Sys_Counter16() - started) < PROVIDER_WARMUP)
        Idle();

    started = Sys_Counter16();
    do {
        if (DNS_Resolve(_symbank, host, ip) == 0)
            return 0;
        if (_neterr != ERR_TIMEOUT && _neterr != ERR_OFFLINE &&
            _neterr != ERR_NOHW)
            return -1;
        Idle();
    } while ((unsigned short)(Sys_Counter16() - started) < DNS_RETRY_TIMEOUT);
    return -1;
#endif
}

static int run_transaction(unsigned char pass, char *ip) {
    signed char socket;
    unsigned short received;

    Shell_Print("\r\nPass ");
    print_num(pass);
    Shell_Print("\r\n  TCP open... ");
    write_progress(pass == 1 ? "Pass 1: opening" : "Pass 2: opening");
    socket = TCP_OpenClient(ip, -1, PROBE_PORT);
    if (socket < 0) {
        failure_step = "TCP open";
        failure_error = (unsigned char)_neterr;
        print_error();
        return -1;
    }
    probe_socket = socket;
    Shell_Print("OK socket=");
    print_num(socket);
    Shell_Print("\r\n");

    Shell_Print("  Send request... ");
    write_progress(pass == 1 ? "Pass 1: sending" : "Pass 2: sending");
    if (TCP_Send((unsigned char)socket, _symbank, request, strlen(request)) < 0) {
        failure_step = "TCP send";
        failure_error = (unsigned char)_neterr;
        print_error();
        TCP_Disconnect((unsigned char)socket);
        return -1;
    }
    Shell_Print("OK\r\n");

    Shell_Print("  Receive/close... ");
    write_progress(pass == 1 ? "Pass 1: receiving" : "Pass 2: receiving");
    memset(response, 0, sizeof(response));
    if (TCP_ReceiveToEnd((unsigned char)socket, _symbank, response,
                         sizeof(response)) < 0) {
        failure_step = "TCP receive";
        failure_error = (unsigned char)_neterr;
        print_error();
        return -1;
    }
    received = (unsigned short)_tcp_progress;
    received_total += received;
    write_progress(pass == 1 ? "Pass 1: complete" : "Pass 2: complete");
    Shell_Print("OK bytes=");
    print_num(received);
    Shell_Print("\r\n");

    return 0;
}

int main(void) {
    char ip[4];
    int first;
    int second;

    Shell_Print("UNAPI network autostart test\r\n");
    _nettimeout = NETWORK_TIMEOUT;
    Shell_Print("Waiting for network daemon... ");
    if (network_when_ready(ip) < 0) {
        if (_neterr == ERR_OFFLINE || _neterr == ERR_NOHW)
            failure_step = "Network daemon";
        else
            failure_step = "DNS";
        failure_error = (unsigned char)_neterr;
        print_error();
        show_result("FAIL");
        return 1;
    }
    Shell_Print("OK pid=");
    print_num(_netpid);
    Shell_Print(" ip=");
    print_ip(ip);
    Shell_Print("\r\n");

    first = run_transaction(1, ip);
    second = run_transaction(2, ip);

    Shell_Print("\r\nResult: ");
    if (!first && !second) {
        Shell_Print("PASS - TCP TX, RX and socket reuse\r\n");
        show_result("PASS");
        return 0;
    }
    Shell_Print("FAIL - see the first failing step above\r\n");
    show_result("FAIL");
    return 1;
}
