// RUN: tf-tfrt-opt -split-input-file -tf-mlrt-async-while %s | FileCheck %s

// This is a simple case that should be pipelined.

// CHECK-LABEL: func.func private @"map/while_cond"
func.func private @"map/while_cond"(%loop_count: tensor<i32>, %max_iterations: tensor<i32>, %handle: tensor<?x!tf_type.resource>, %flow_in: tensor<*xf32>, %matrix: tensor<3x3xf32>) -> tensor<i1> {
  %0 = "tf.Less"(%loop_count, %max_iterations) : (tensor<i32>, tensor<i32>) -> tensor<i1>
  return %0 : tensor<i1>
}

// CHECK-LABEL: func.func private @"map/while_cond/TfMlrtAsyncWhilePredicate"(%arg0: tensor<i32>, %arg1: tensor<i32>) -> tensor<i1> {
// CHECK-NEXT:    %0 = "tf.Less"(%arg0, %arg1) : (tensor<i32>, tensor<i32>) -> tensor<i1>
// CHECK-NEXT:    return %0 : tensor<i1>

// CHECK-LABEL: func.func private @"map/while_body"
func.func private @"map/while_body"(%loop_count: tensor<i32>, %max_iterations: tensor<i32>, %handle: tensor<?x!tf_type.resource>, %flow_in: tensor<*xf32>, %matrix: tensor<3x3xf32>) -> (tensor<i32>, tensor<i32>, tensor<?x!tf_type.resource>, tensor<*xf32>, tensor<3x3xf32>) {
  %cst_1 = "tf.Const"() {value = dense<1> : tensor<i32>} : () -> tensor<i32>
  %0 = "tf.AddV2"(%loop_count, %cst_1) : (tensor<i32>, tensor<i32>) -> tensor<i32>
  %1 = "tf.TensorArrayReadV3"(%handle, %loop_count, %flow_in) : (tensor<?x!tf_type.resource>, tensor<i32>, tensor<*xf32>) -> tensor<3x3xf32>
  %2 = "tf.MatMul"(%1, %matrix)  : (tensor<3x3xf32>, tensor<3x3xf32>) -> tensor<3x3xf32>
  return %0, %max_iterations, %handle, %flow_in, %2: tensor<i32>, tensor<i32>, tensor<?x!tf_type.resource>, tensor<*xf32>, tensor<3x3xf32>
}

// CHECK-LABEL: func.func private @"map/while_body/TfMlrtAsyncWhileBody"(%arg0: !mlrt.promise, %arg1: !mlrt.future, %arg2: !mlrt.promise, %arg3: !mlrt.future, %arg4: !mlrt.promise, %arg5: tensor<i32>, %arg6: tensor<?x!tf_type.resource>, %arg7: tensor<*xf32>) {
// CHECK-NEXT:    %cst = "tf.Const"() {value = dense<1> : tensor<i32>} : () -> tensor<i32>
// CHECK-NEXT:    %0 = "tf_mlrt.tf_await"(%arg1) : (!mlrt.future) -> tensor<i32>
// CHECK-NEXT:    %1 = "tf.AddV2"(%0, %cst) : (tensor<i32>, tensor<i32>) -> tensor<i32>
// CHECK-NEXT:    "tf_mlrt.tf_promise"(%arg2, %1) : (!mlrt.promise, tensor<i32>) -> ()
// CHECK-NEXT:    %2 = "tf.PartitionedCall"(%1, %arg5) {config = "", config_proto = "", executor_type = "", f = @"map/while_cond/TfMlrtAsyncWhilePredicate"} : (tensor<i32>, tensor<i32>) -> tensor<i1>
// CHECK-NEXT:    "tf_mlrt.tf_promise"(%arg0, %2) : (!mlrt.promise, tensor<i1>) -> ()
// CHECK-NEXT:    %3 = "tf.TensorArrayReadV3"(%arg6, %0, %arg7) : (tensor<?x!tf_type.resource>, tensor<i32>, tensor<*xf32>) -> tensor<3x3xf32>
// CHECK-NEXT:    %4 = "tf_mlrt.tf_await"(%arg3) : (!mlrt.future) -> tensor<3x3xf32>
// CHECK-NEXT:    %5 = "tf.MatMul"(%3, %4) : (tensor<3x3xf32>, tensor<3x3xf32>) -> tensor<3x3xf32>
// CHECK-NEXT:    "tf_mlrt.tf_promise"(%arg4, %5) : (!mlrt.promise, tensor<3x3xf32>) -> ()
// CHECK-NEXT:    return

//CHECK-LABEL: func.func @serving_default
func.func @serving_default(%max_iterations: tensor<i32>, %array_handle: tensor<?x!tf_type.resource>, %array_flow: tensor<*xf32>, %matrix: tensor<3x3xf32>) -> (tensor<3x3xf32>, tensor<*xf32>) {
  %cst_0 = "tf.Const"() {value = dense<0> : tensor<i32>} : () -> tensor<i32>
  // CHECK: %0 = "tf.PartitionedCall"(%cst, %arg0) {config = "", config_proto = "", executor_type = "", f = @"map/while_cond/TfMlrtAsyncWhilePredicate"} : (tensor<i32>, tensor<i32>) -> tensor<i1>
  // CHECK-NEXT: %1:6 = tf_mlrt.tf_async_while @"map/while_body/TfMlrtAsyncWhileBody"(%0, %cst, %arg3, %arg0, %arg1, %arg2) {invariant_size = 3 : i32} : (tensor<i1>, tensor<i32>, tensor<3x3xf32>, tensor<i32>, tensor<?x!tf_type.resource>, tensor<*xf32>) -> (!mlrt.future, !mlrt.future, !mlrt.future, !mlrt.future, !mlrt.future, !mlrt.future)
  %1:5 = "tf.While"(%cst_0, %max_iterations, %array_handle, %array_flow, %matrix) {body= @"map/while_body", cond = @"map/while_cond", is_stateless = false, parallel_iterations = 10 : i64, shape_invariant} : (tensor<i32>, tensor<i32>, tensor<?x!tf_type.resource>, tensor<*xf32>, tensor<3x3xf32>) ->  (tensor<i32>, tensor<i32>, tensor<?x!tf_type.resource>, tensor<*xf32>, tensor<3x3xf32>)
  // CHECK-NEXT: %2 = "tf_mlrt.tf_await"(%1#5) : (!mlrt.future) -> tensor<*xf32>
  // CHECK-NEXT: %3 = "tf_mlrt.tf_await"(%1#2) : (!mlrt.future) -> tensor<3x3xf32>
  // CHECK-NEXT:  return %3, %2 : tensor<3x3xf32>, tensor<*xf32>
  return %1#4, %1#3 : tensor<3x3xf32>, tensor<*xf32>
}


//CHECK-LABEL: func.func @multi_while_test
func.func @multi_while_test(%max_iterations: tensor<i32>, %array_handle: tensor<?x!tf_type.resource>, %array_flow: tensor<*xf32>, %matrix: tensor<3x3xf32>, %array_handle_2: tensor<?x!tf_type.resource>, %array_flow_2: tensor<*xf32>, %matrix_2: tensor<3x3xf32>) -> (tensor<3x3xf32>, tensor<3x3xf32>) {
  %cst_0 = "tf.Const"() {value = dense<0> : tensor<i32>} : () -> tensor<i32>
  // CHECK: %0 = "tf.PartitionedCall"(%cst, %arg0) {config = "", config_proto = "", executor_type = "", f = @"map/while_cond/TfMlrtAsyncWhilePredicate"} : (tensor<i32>, tensor<i32>) -> tensor<i1>
  // CHECK-NEXT: %1:6 = tf_mlrt.tf_async_while @"map/while_body/TfMlrtAsyncWhileBody"(%0, %cst, %arg3, %arg0, %arg1, %arg2) {invariant_size = 3 : i32} : (tensor<i1>, tensor<i32>, tensor<3x3xf32>, tensor<i32>, tensor<?x!tf_type.resource>, tensor<*xf32>) -> (!mlrt.future, !mlrt.future, !mlrt.future, !mlrt.future, !mlrt.future, !mlrt.future)
  %1:5 = "tf.While"(%cst_0, %max_iterations, %array_handle, %array_flow, %matrix) {body= @"map/while_body", cond = @"map/while_cond", is_stateless = false, parallel_iterations = 10 : i64, shape_invariant} : (tensor<i32>, tensor<i32>, tensor<?x!tf_type.resource>, tensor<*xf32>, tensor<3x3xf32>) ->  (tensor<i32>, tensor<i32>, tensor<?x!tf_type.resource>, tensor<*xf32>, tensor<3x3xf32>)
  // CHECK: %2 = "tf.PartitionedCall"(%cst, %arg0) {config = "", config_proto = "", executor_type = "", f = @"map/while_cond/TfMlrtAsyncWhilePredicate"} : (tensor<i32>, tensor<i32>) -> tensor<i1>
  // CHECK-NEXT: %3:6 = tf_mlrt.tf_async_while @"map/while_body/TfMlrtAsyncWhileBody"(%2, %cst, %arg6, %arg0, %arg4, %arg5) {invariant_size = 3 : i32} : (tensor<i1>, tensor<i32>, tensor<3x3xf32>, tensor<i32>, tensor<?x!tf_type.resource>, tensor<*xf32>) -> (!mlrt.future, !mlrt.future, !mlrt.future, !mlrt.future, !mlrt.future, !mlrt.future)
  %2:5 = "tf.While"(%cst_0, %max_iterations, %array_handle_2, %array_flow_2, %matrix_2) {body= @"map/while_body", cond = @"map/while_cond", is_stateless = false, parallel_iterations = 10 : i64, shape_invariant} : (tensor<i32>, tensor<i32>, tensor<?x!tf_type.resource>, tensor<*xf32>, tensor<3x3xf32>) ->  (tensor<i32>, tensor<i32>, tensor<?x!tf_type.resource>, tensor<*xf32>, tensor<3x3xf32>)
  // CHECK-NEXT: %4 = "tf_mlrt.tf_await"(%1#2) : (!mlrt.future) -> tensor<3x3xf32>
  // CHECK-NEXT: %5 = "tf_mlrt.tf_await"(%3#2) : (!mlrt.future) -> tensor<3x3xf32>
  // CHECK-NEXT:  return %4, %5 : tensor<3x3xf32>, tensor<3x3xf32>
  return %1#4, %2#4 : tensor<3x3xf32>, tensor<3x3xf32>
}

// -----

// Test a case in which predicate is updated after mutables and shall not be converted to AsyncWhile.

// CHECK-LABEL: func.func private @"map/while_cond"
func.func private @"map/while_cond"(%loop_count: tensor<i32>, %max_iterations: tensor<i32>, %handle: tensor<?x!tf_type.resource>, %flow_in: tensor<*xf32>, %matrix: tensor<3x3xf32>) -> tensor<i1> {
  %0 = "tf.Less"(%loop_count, %max_iterations) : (tensor<i32>, tensor<i32>) -> tensor<i1>
  return %0 : tensor<i1>
}

// CHECK-LABEL: func.func private @"map/while_body"
func.func private @"map/while_body"(%loop_count: tensor<i32>, %max_iterations: tensor<i32>, %handle: tensor<?x!tf_type.resource>, %flow_in: tensor<*xf32>, %matrix: tensor<3x3xf32>) -> (tensor<i32>, tensor<i32>, tensor<?x!tf_type.resource>, tensor<*xf32>, tensor<3x3xf32>) {
  %cst_1 = "tf.Const"() {value = dense<1> : tensor<i32>} : () -> tensor<i32>
  %1 = "tf.TensorArrayReadV3"(%handle, %loop_count, %flow_in) : (tensor<?x!tf_type.resource>, tensor<i32>, tensor<*xf32>) -> tensor<3x3xf32>
  %2 = "tf.MatMul"(%1, %matrix)  : (tensor<3x3xf32>, tensor<3x3xf32>) -> tensor<3x3xf32>
  // Predicate is update at the last stage.
  %0 = "tf.AddV2"(%loop_count, %cst_1) : (tensor<i32>, tensor<i32>) -> tensor<i32>
  return %0, %max_iterations, %handle, %flow_in, %2: tensor<i32>, tensor<i32>, tensor<?x!tf_type.resource>, tensor<*xf32>, tensor<3x3xf32>
}

//CHECK-LABEL: func.func @serving_default
func.func @serving_default(%max_iterations: tensor<i32>, %array_handle: tensor<?x!tf_type.resource>, %array_flow: tensor<*xf32>, %matrix: tensor<3x3xf32>) -> tensor<3x3xf32> {
  %cst_0 = "tf.Const"() {value = dense<0> : tensor<i32>} : () -> tensor<i32>
  // CHECK: tf.While
  // CHECK-NOT: AsyncWhile
  %1:5 = "tf.While"(%cst_0, %max_iterations, %array_handle, %array_flow, %matrix) {body= @"map/while_body", cond = @"map/while_cond", is_stateless = false, parallel_iterations = 10 : i64, shape_invariant} : (tensor<i32>, tensor<i32>, tensor<?x!tf_type.resource>, tensor<*xf32>, tensor<3x3xf32>) ->  (tensor<i32>, tensor<i32>, tensor<?x!tf_type.resource>, tensor<*xf32>, tensor<3x3xf32>)
  return %1#4 : tensor<3x3xf32>
}

// -----

// The newly create function name may have conflict with existing functions (very rare).

// CHECK-LABEL: func.func private @"random/while_cond/TfMlrtAsyncWhilePredicate"(%arg0: tensor<i32>, %arg1: tensor<i32>) -> tensor<i32> {
func.func private @"random/while_cond/TfMlrtAsyncWhilePredicate"(%arg0: tensor<i32>, %arg1: tensor<i32>) -> tensor<i32> {

  %0 = "tf.AddV2"(%arg0, %arg1) : (tensor<i32>, tensor<i32>) -> tensor<i32>
  return %0: tensor<i32>
}

// CHECK-LABEL: func.func private @"random/while_body/TfMlrtAsyncWhileBody"(%arg0: tensor<i32>, %arg1: tensor<i32>) -> tensor<i32> {
func.func private @"random/while_body/TfMlrtAsyncWhileBody"(%arg0: tensor<i32>, %arg1: tensor<i32>) -> tensor<i32> {
  %0 = "tf.AddV2"(%arg0, %arg1) : (tensor<i32>, tensor<i32>) -> tensor<i32>
  return %0: tensor<i32>
}

// CHECK-LABEL: func.func private @"random/while_cond"
func.func private @"random/while_cond"(%loop_count: tensor<i32>, %max_iterations: tensor<i32>, %handle: tensor<?x!tf_type.resource>, %flow_in: tensor<*xf32>, %matrix: tensor<3x3xf32>) -> tensor<i1> {
  %0 = "tf.Less"(%loop_count, %max_iterations) : (tensor<i32>, tensor<i32>) -> tensor<i1>
  return %0 : tensor<i1>
}

// CHECK-LABEL: func.func private @"random/while_cond/TfMlrtAsyncWhilePredicate_0"(%arg0: tensor<i32>, %arg1: tensor<i32>) -> tensor<i1> {
// CHECK-NEXT:    %0 = "tf.Less"(%arg0, %arg1) : (tensor<i32>, tensor<i32>) -> tensor<i1>
// CHECK-NEXT:    return %0 : tensor<i1>

// CHECK-LABEL: func.func private @"random/while_body"
func.func private @"random/while_body"(%loop_count: tensor<i32>, %max_iterations: tensor<i32>, %handle: tensor<?x!tf_type.resource>, %flow_in: tensor<*xf32>, %matrix: tensor<3x3xf32>) -> (tensor<i32>, tensor<i32>, tensor<?x!tf_type.resource>, tensor<*xf32>, tensor<3x3xf32>) {
  %cst_1 = "tf.Const"() {value = dense<1> : tensor<i32>} : () -> tensor<i32>
  %0 = "tf.AddV2"(%loop_count, %cst_1) : (tensor<i32>, tensor<i32>) -> tensor<i32>
  %1 = "tf.TensorArrayReadV3"(%handle, %loop_count, %flow_in) : (tensor<?x!tf_type.resource>, tensor<i32>, tensor<*xf32>) -> tensor<3x3xf32>
  %2 = "tf.MatMul"(%1, %matrix)  : (tensor<3x3xf32>, tensor<3x3xf32>) -> tensor<3x3xf32>
  return %0, %max_iterations, %handle, %flow_in, %2: tensor<i32>, tensor<i32>, tensor<?x!tf_type.resource>, tensor<*xf32>, tensor<3x3xf32>
}

// CHECK-LABEL: func.func private @"random/while_body/TfMlrtAsyncWhileBody_1"(%arg0: !mlrt.promise, %arg1: !mlrt.future, %arg2: !mlrt.promise, %arg3: !mlrt.future, %arg4: !mlrt.promise, %arg5: tensor<i32>, %arg6: tensor<?x!tf_type.resource>, %arg7: tensor<*xf32>) {
// CHECK-NEXT:    %cst = "tf.Const"() {value = dense<1> : tensor<i32>} : () -> tensor<i32>
// CHECK-NEXT:    %0 = "tf_mlrt.tf_await"(%arg1) : (!mlrt.future) -> tensor<i32>
// CHECK-NEXT:    %1 = "tf.AddV2"(%0, %cst) : (tensor<i32>, tensor<i32>) -> tensor<i32>
// CHECK-NEXT:    "tf_mlrt.tf_promise"(%arg2, %1) : (!mlrt.promise, tensor<i32>) -> ()
// CHECK-NEXT:    %2 = "tf.PartitionedCall"(%1, %arg5) {config = "", config_proto = "", executor_type = "", f = @"random/while_cond/TfMlrtAsyncWhilePredicate_0"} : (tensor<i32>, tensor<i32>) -> tensor<i1>
// CHECK-NEXT:    "tf_mlrt.tf_promise"(%arg0, %2) : (!mlrt.promise, tensor<i1>) -> ()
// CHECK-NEXT:    %3 = "tf.TensorArrayReadV3"(%arg6, %0, %arg7) : (tensor<?x!tf_type.resource>, tensor<i32>, tensor<*xf32>) -> tensor<3x3xf32>
// CHECK-NEXT:    %4 = "tf_mlrt.tf_await"(%arg3) : (!mlrt.future) -> tensor<3x3xf32>
// CHECK-NEXT:    %5 = "tf.MatMul"(%3, %4) : (tensor<3x3xf32>, tensor<3x3xf32>) -> tensor<3x3xf32>
// CHECK-NEXT:    "tf_mlrt.tf_promise"(%arg4, %5) : (!mlrt.promise, tensor<3x3xf32>) -> ()
// CHECK-NEXT:    return

//CHECK-LABEL: func.func @random_serving_default
func.func @random_serving_default(%max_iterations: tensor<i32>, %array_handle: tensor<?x!tf_type.resource>, %array_flow: tensor<*xf32>, %matrix: tensor<3x3xf32>) -> (tensor<3x3xf32>, tensor<*xf32>) {
  %cst_0 = "tf.Const"() {value = dense<0> : tensor<i32>} : () -> tensor<i32>
  // CHECK: %0 = "tf.PartitionedCall"(%cst, %arg0) {config = "", config_proto = "", executor_type = "", f = @"random/while_cond/TfMlrtAsyncWhilePredicate_0"} : (tensor<i32>, tensor<i32>) -> tensor<i1>
  // CHECK-NEXT: %1:6 = tf_mlrt.tf_async_while @"random/while_body/TfMlrtAsyncWhileBody_1"(%0, %cst, %arg3, %arg0, %arg1, %arg2) {invariant_size = 3 : i32} : (tensor<i1>, tensor<i32>, tensor<3x3xf32>, tensor<i32>, tensor<?x!tf_type.resource>, tensor<*xf32>) -> (!mlrt.future, !mlrt.future, !mlrt.future, !mlrt.future, !mlrt.future, !mlrt.future)
  %1:5 = "tf.While"(%cst_0, %max_iterations, %array_handle, %array_flow, %matrix) {body= @"random/while_body", cond = @"random/while_cond", is_stateless = false, parallel_iterations = 10 : i64, shape_invariant} : (tensor<i32>, tensor<i32>, tensor<?x!tf_type.resource>, tensor<*xf32>, tensor<3x3xf32>) ->  (tensor<i32>, tensor<i32>, tensor<?x!tf_type.resource>, tensor<*xf32>, tensor<3x3xf32>)
  // CHECK-NEXT: %2 = "tf_mlrt.tf_await"(%1#5) : (!mlrt.future) -> tensor<*xf32>
  // CHECK-NEXT: %3 = "tf_mlrt.tf_await"(%1#2) : (!mlrt.future) -> tensor<3x3xf32>
  // CHECK-NEXT:  return %3, %2 : tensor<3x3xf32>, tensor<*xf32>
  return %1#4, %1#3 : tensor<3x3xf32>, tensor<*xf32>
}

