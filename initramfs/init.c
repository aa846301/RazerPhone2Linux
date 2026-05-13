#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/reboot.h>
#include <fcntl.h>
#include <string.h>
#include <dirent.h>
#include <errno.h>
#include <linux/reboot.h>
#include <sys/sysmacros.h>

static void run_shell(void);
static int do_mount(const char *src, const char *tgt, const char *fs, unsigned long flags);

int main(void) {
    do_mount("none", "/proc", "proc", 0);
    do_mount("none", "/sys", "sysfs", 0);
    do_mount("none", "/dev", "devtmpfs", 0);
    mkdir("/dev/pts", 0755);
    do_mount("devpts", "/dev/pts", "devpts", 0);
    mkdir("/run", 0755);

    printf("\n=== Razer Phone 2 initramfs (static C) ===\n");
    printf("Waiting for UFS storage...\n");

    int waited = 0;
    while (waited < 15) {
        struct stat st;
        if (stat("/dev/sda", &st) == 0 || stat("/dev/mmcblk0", &st) == 0)
            break;
        sleep(1);
        waited++;
        printf("  waiting... %ds\n", waited);
    }
    sleep(2);

    /* Debug info */
    printf("--- /proc/partitions ---\n");
    FILE *f = fopen("/proc/partitions", "r");
    if (f) { char buf[256]; while(fgets(buf,sizeof(buf),f)) fputs(buf,stdout); fclose(f); }

    /* Scan sysfs for partition labels */
    printf("--- Partition labels ---\n");
    mkdir("/dev/disk", 0755);
    mkdir("/dev/disk/by-partlabel", 0755);

    DIR *d = opendir("/sys/class/block");
    char root_dev[128] = {0};
    if (d) {
        struct dirent *ent;
        while ((ent = readdir(d))) {
            if (ent->d_name[0] == '.') continue;
            char path[512], partname[128];
            int major_n, minor_n;

            snprintf(path, sizeof(path), "/sys/class/block/%s/partition", ent->d_name);
            if (access(path, F_OK) != 0) continue;

            snprintf(path, sizeof(path), "/sys/class/block/%s/uevent", ent->d_name);
            f = fopen(path, "r");
            major_n = minor_n = -1;
            if (f) {
                char line[256];
                while (fgets(line, sizeof(line), f)) {
                    sscanf(line, "MAJOR=%d", &major_n);
                    sscanf(line, "MINOR=%d", &minor_n);
                }
                fclose(f);
            }

            snprintf(path, sizeof(path), "/sys/class/block/%s/partname", ent->d_name);
            f = fopen(path, "r");
            partname[0] = 0;
            if (f) {
                if (fgets(partname, sizeof(partname), f)) {
                    partname[strcspn(partname, "\n")] = 0;
                }
                fclose(f);
            }

            if (partname[0] && major_n >= 0 && minor_n >= 0) {
                snprintf(path, sizeof(path), "/dev/disk/by-partlabel/%s", partname);
                mknod(path, S_IFBLK | 0660, makedev(major_n, minor_n));
                printf("  %s -> /dev/%s (%d:%d)\n", partname, ent->d_name, major_n, minor_n);
                if (strcmp(partname, "userdata") == 0) {
                    snprintf(root_dev, sizeof(root_dev), "/dev/disk/by-partlabel/userdata");
                }
            }
        }
        closedir(d);
    }

    /* Fallback: try sda partitions */
    if (!root_dev[0]) {
        const char *devs[] = {"/dev/sda17","/dev/sda18","/dev/sda19","/dev/sda20","/dev/sda16",NULL};
        for (int i = 0; devs[i]; i++) {
            struct stat st;
            if (stat(devs[i], &st) == 0) {
                strncpy(root_dev, devs[i], sizeof(root_dev)-1);
                printf("  Fallback: using %s\n", root_dev);
                break;
            }
        }
    }

    if (!root_dev[0]) {
        printf("\n!!! ERROR: Cannot find root device !!!\n");
        printf("Dropping to halt...\n");
        run_shell();
        return 1;
    }

    printf("Mounting root: %s\n", root_dev);
    mkdir("/sysroot", 0755);
    if (mount(root_dev, "/sysroot", "ext4", 0, NULL) != 0) {
        printf("Mount rw failed (%s), trying ro...\n", strerror(errno));
        if (mount(root_dev, "/sysroot", "ext4", MS_RDONLY, NULL) != 0) {
            printf("!!! Mount failed: %s !!!\n", strerror(errno));
            run_shell();
            return 1;
        }
    }

    printf("Root mounted. Switching root...\n");
    umount("/dev/pts");
    umount("/proc");
    umount("/sys");

    chdir("/sysroot");
    mount(".", "/", NULL, MS_MOVE, NULL);
    chroot(".");
    chdir("/");

    char *argv[] = {"/sbin/init", NULL};
    char *envp[] = {"HOME=/root", "PATH=/sbin:/bin:/usr/sbin:/usr/bin", "TERM=linux", NULL};
    execve("/sbin/init", argv, envp);
    printf("execve /sbin/init failed: %s\n", strerror(errno));

    /* fallback */
    argv[0] = "/bin/sh";
    execve("/bin/sh", argv, envp);
    printf("execve /bin/sh failed: %s\n", strerror(errno));
    run_shell();
    return 1;
}

static void run_shell(void) {
    printf("No shell available (static init only). Halting.\n");
    sync();
    while(1) sleep(3600);
}

static int do_mount(const char *src, const char *tgt, const char *fs, unsigned long flags) {
    mkdir(tgt, 0755);
    return mount(src, tgt, fs, flags, NULL);
}
