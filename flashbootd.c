#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <android/log.h>
#include <sys/types.h>

#define logd(...) __android_log_print(ANDROID_LOG_DEBUG , "Kernel Installer", __VA_ARGS__)
#define loge(...) __android_log_print(ANDROID_LOG_ERROR , "Kernel Installer", __VA_ARGS__)

int main()
{
   pid_t pid, sid;
   pid = fork();
   if (pid < 0) {
      exit(76);
   }
   sid = setsid();
   if (sid < 0) {
      exit(77);
   }
   logd( "Kernel Installer Started! Executing flashboot script" );
   char *argv[] = { NULL };
   execv( "/system/bin/flashboot.sh", argv );
   loge( "Failed to execute /system/bin/flashboot.sh" );
   return 78;
}
