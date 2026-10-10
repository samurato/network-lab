# terraform/ (phase 4)

Terraform is the front door for everything outside the lab host, and wraps the lab lifecycle:
- `aws-hybrid/` — VPC + EC2 workload, Transit Gateway, Site-to-Site VPN to a lab cloud-edge router, VPC Flow Logs
- `elastic/`    — Elastic Cloud deployment (`elastic/ec`), OTLP API key, data streams
- lab wrapper   — `terraform_data` resources running `make build/apply` when intent hashes change
Device-level diffs stay with `make plan` (AVD/Ansible); no Terraform provider exists for EOS device config.
