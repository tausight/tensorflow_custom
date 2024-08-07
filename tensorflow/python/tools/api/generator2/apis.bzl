"""generate_api API definitions."""

load(":patterns.bzl", "compile_patterns")

APIS = {
    "keras": {
        "decorator": "tensorflow.python.util.tf_export.keras_export",
        "target_patterns": compile_patterns([
            "//third_party/py/keras/...",
        ]),
    },
    "tensorflow": {
        "decorator": "tensorflow.python.util.tf_export.tf_export",
        "target_patterns": compile_patterns([
            "//tensorflow/python/...",
            "//tensorflow/dtensor/python:accelerator_util",
            "//tensorflow/dtensor/python:api",
            "//tensorflow/dtensor/python:config",
            "//tensorflow/dtensor/python:d_checkpoint",
            "//tensorflow/dtensor/python:d_variable",
            "//tensorflow/dtensor/python:input_util",
            "//tensorflow/dtensor/python:layout",
            "//tensorflow/dtensor/python:mesh_util",
            "//tensorflow/dtensor/python:tpu_util",
            "//tensorflow/dtensor/python:save_restore",
            "//tensorflow/lite/python/...",
            "//tensorflow/python:modules_with_exports",
            "//tensorflow/lite/tools/optimize/debugging/python:all",
        ]),
    },
    "tensorflow_estimator": {
        "decorator": "tensorflow_estimator.python.estimator.estimator_export.estimator_export",
        "target_patterns": compile_patterns([
            "//tensorflow_estimator/...",
        ]),
    },
}
