#include <jni.h>
#include <stdlib.h>
extern char *PerformRequest(char *input);
JNIEXPORT jstring JNICALL Java_dev_dualforum_forum_1app_EchBridge_request(JNIEnv *env, jclass clazz, jstring input) {
    (void)clazz;
    const char *value = (*env)->GetStringUTFChars(env, input, 0);
    if (value == 0) return NULL;
    char *result = PerformRequest((char *)value);
    (*env)->ReleaseStringUTFChars(env, input, value);
    if (result == 0) return NULL;
    jstring output = (*env)->NewStringUTF(env, result);
    free(result);
    return output;
}
