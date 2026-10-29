output "zone_id" {
  description = "Route53 private hosted zone ID"
  value       = aws_route53_zone.private.zone_id
}

output "zone_name" {
  description = "Route53 private hosted zone name"
  value       = aws_route53_zone.private.name
}

output "name_servers" {
  description = "Zone name servers (not used for private zones, but exported for reference)"
  value       = aws_route53_zone.private.name_servers
}
