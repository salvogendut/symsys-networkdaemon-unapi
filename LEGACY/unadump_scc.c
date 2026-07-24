#include <stdlib.h>
#include <symbos.h>
#include <symbos/file.h>

static char path[] = "A:/SYMUNAPI.DAT";
static unsigned char buf[32];
static char numbuf[8];
static char hex[] = "0123456789ABCDEF";

static void pnum(int value) {
    itoa(value, numbuf, 10);
    Shell_Print(numbuf);
}

static void phex(unsigned char value) {
    char out[4];
    out[0] = hex[value >> 4];
    out[1] = hex[value & 15];
    out[2] = ' ';
    out[3] = 0;
    Shell_Print(out);
}

static unsigned short word_at(int offset) {
    return (unsigned short)buf[offset] | ((unsigned short)buf[offset + 1] << 8);
}

int main(int argc, char **argv) {
    unsigned char fd;
    unsigned short got;
    int i;

    Shell_Print("SYMUNAPI.DAT dump\r\n");
    fd = File_Open(_symbank, path);
    if (fd > 15) {
        Shell_Print("open fail ");
        pnum(fd);
        Shell_Print("\r\n");
        return 1;
    }
    got = File_Read(fd, _symbank, buf, sizeof(buf));
    File_Close(fd);
    Shell_Print("bytes=");
    pnum(got);
    Shell_Print("\r\n");
    for (i = 0; i < 32; ++i) {
        phex(buf[i]);
        if ((i & 15) == 15)
            Shell_Print("\r\n");
    }
    Shell_Print("kind=");
    pnum(buf[10]);
    Shell_Print(" seg=");
    pnum(buf[12]);
    Shell_Print(" entry=");
    pnum(word_at(13));
    Shell_Print(" helper=");
    pnum(word_at(15));
    Shell_Print("\r\nputp1=");
    pnum(word_at(27));
    Shell_Print(" getp1=");
    pnum(word_at(29));
    Shell_Print("\r\n");
    return 0;
}
