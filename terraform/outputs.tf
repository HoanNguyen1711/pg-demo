output "endpoint" {
  value = aws_db_instance.demo.address
}

output "bastion_id" {
  value = aws_instance.bastion.id
}

output "master_secret_arn" {
  value = aws_db_instance.demo.master_user_secret[0].secret_arn
}

output "tunnel_command" {
  description = "Run in its own terminal and leave it open: eval \"$(terraform output -raw tunnel_command)\""
  value = join(" ", [
    "aws ssm start-session --region ${var.region}",
    "--target ${aws_instance.bastion.id}",
    "--document-name AWS-StartPortForwardingSessionToRemoteHost",
    "--parameters '{\"host\":[\"${aws_db_instance.demo.address}\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"${var.local_port}\"]}'",
  ])
}

output "psql_command" {
  description = "Run while the tunnel is open: eval \"$(terraform output -raw psql_command)\""
  value = join(" ", [
    "PGPASSWORD=\"$(aws secretsmanager get-secret-value --region ${var.region}",
    "--secret-id '${aws_db_instance.demo.master_user_secret[0].secret_arn}'",
    "--query SecretString --output text | jq -r .password)\"",
    "psql 'host=localhost port=${var.local_port} dbname=demo user=demo_admin sslmode=require'",
  ])
}
