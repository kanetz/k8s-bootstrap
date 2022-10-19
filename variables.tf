# Master节点配置
variable "master_count" {
  description = "Master节点VM数量"
  default     = 1
}
variable "master_cpu_core_count" {
  description = "Master节点CPU核心数"
  default     = 2
}
variable "master_memory_size_gb" {
  description = "Master节点内存大小（GB）"
  default     = 4
}

# Worker节点配置
variable "worker_count" {
  description = "Worker节点VM数量"
  default     = 1
}
variable "worker_cpu_core_count" {
  description = "Worker节点CPU核心数"
  default     = 2
}
variable "worker_memory_size_gb" {
  description = "Worker节点内存大小（GB）"
  default     = 4
}
