output "node_ips" {
  value = { for k, n in var.nodes : k => n.ip }
}