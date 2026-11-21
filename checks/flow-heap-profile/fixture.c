#define _GNU_SOURCE
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

void *retained_profile_memory;

__attribute__((noinline)) void retain_profile_memory(void) {
    retained_profile_memory = malloc(65536);
    assert(retained_profile_memory != NULL);
    memset(retained_profile_memory, 42, 65536);
}

int main(int argc, char **argv) {
    assert(argc == 2);
    assert(getenv("LD_PRELOAD") == NULL);
    assert(getenv("DUMP_HEAPTRACK_OUTPUT") == NULL);
    FILE *maps = fopen("/proc/self/maps", "r");
    assert(maps != NULL);
    char line[4096];
    int loaded = 0;
    while (fgets(line, sizeof(line), maps))
        loaded |= strstr(line, "libheaptrack_preload.so") != NULL;
    fclose(maps);
    if (strcmp(argv[1], "child") == 0) {
        assert(!loaded);
        return 0;
    }
    assert(strcmp(argv[1], "main") == 0);
    assert(loaded);
    retain_profile_memory();
    pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        execl(argv[0], argv[0], "child", (char *)NULL);
        _exit(91);
    }
    int status;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    int notification = socket(AF_UNIX, SOCK_DGRAM, 0);
    assert(notification >= 0);
    struct sockaddr_un address = { .sun_family = AF_UNIX };
    const char *path = getenv("NOTIFY_SOCKET");
    assert(path != NULL && strlen(path) < sizeof(address.sun_path));
    strcpy(address.sun_path, path);
    assert(sendto(notification, "READY=1", 7, 0,
                  (struct sockaddr *)&address, sizeof(address)) == 7);
    close(notification);
    printf("TARGET_PID %ld\n", (long)getpid());
    return 0;
}
