# tflite_flutter references the optional TFLite GPU delegate reflectively.
# This project doesn't depend on org.tensorflow:tensorflow-lite-gpu, so the
# class is genuinely absent at build time (never loaded at runtime either) —
# tell R8 not to fail on it.
-dontwarn org.tensorflow.lite.gpu.**
