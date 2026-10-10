# PostgreSQL tuning demo (DE class, Oct 10)

Scripts that reproduce every example on the slides. Tested on PostgreSQL 16.

## Before the talk (do this at home, not in class)

```bash
docker compose up -d
docker compose exec db psql -U postgres -f /demo/00_setup.sql     # ~1 min, 10M orders + 1M customers
```

Data: `orders` (10M rows, ~650 MB) with a skewed status (completed 90%, shipped 5%,
cancelled 3.9%, pending 1%, refunded 0.1%), `created_at` over 2024-10-10 .. 2026-10-10,
and customer 42 with a fixed order history. `customers` (1M rows, mixed-case emails).

Quick test on a slow laptop: `psql -U postgres -v rows=1000000 -f /demo/00_setup.sql`.

## Running on RDS instead of Docker

The database is private: no public IP, no internet gateway. You reach it through an SSM
port-forwarding session via a small bastion EC2 that has no SSH key and no inbound rules:

```
laptop :15432 --(HTTPS 443, SSM)--> VPC endpoints --> bastion EC2 --(5432)--> RDS
```

Needs: AWS CLI v2, the Session Manager plugin (`brew install --cask session-manager-plugin`), `jq`, `psql`.

```bash
aws login --region ap-southeast-1                  # browser sign-in, no access keys
cd terraform
cp terraform.tfvars.example terraform.tfvars      # optional edits
terraform init && terraform apply                  # ~10 min to create the instance

# terminal 1: open the tunnel and leave it running
eval "$(terraform output -raw tunnel_command)"

# terminal 2: psql through the tunnel (password is read from Secrets Manager)
eval "$(terraform output -raw psql_command)"

# inside psql, from the repo root:
\i sql/00_setup.sql
```

- Instance: `db.t4g.large` (2 vCPU, 8 GiB), gp3 20 GB, PostgreSQL 16, single-AZ, Singapore,
  plus a `t4g.nano` bastion and three SSM interface endpoints.
  Roughly $0.25/hour in total; create it 1-2 days before, `terraform destroy` right after the talk.
- The master password is managed by RDS in Secrets Manager; it is not in the Terraform state.
- The tunnel only needs outbound HTTPS, so it works on networks that block port 5432 and there is
  no IP allow-list to update in class. Keep the Docker setup on your laptop as the backup anyway.
- If Terraform can't use the `aws login` session, export it first:
  `eval "$(aws configure export-credentials --format env)"`.
- The master user is `rds_superuser`, not a real superuser. Everything was designed to work with that,
  except possibly the `heap_page_items` query in `06_mvcc_optional.sql` (pageinspect). Run it once before the talk;
  if it says "permission denied", skip that one query.
- `random_page_cost` is left at 4 (the default) so plans match the slides. On real SSD storage you
  would normally lower it to about 1.1, which is a good point to mention in Q&A.
- Run `00_setup.sql` and every demo once the day before, so you know the timings on this instance.

### Stop and start between rehearsals

Stopping keeps all data. Stopped, the stack still costs about $0.044/hour (~$1/day): the three SSM
VPC endpoints ($0.039/hour, they cannot be stopped), RDS storage, the bastion's EBS volume and the
secret. Running, it is about $0.25/hour. RDS starts itself again after 7 days.

```bash
cd terraform

# stop
aws rds stop-db-instance --db-instance-identifier pg-demo
aws ec2 stop-instances --instance-ids "$(terraform output -raw bastion_id)"

# start (RDS takes 5-10 min)
aws rds start-db-instance --db-instance-identifier pg-demo
aws ec2 start-instances --instance-ids "$(terraform output -raw bastion_id)"
aws rds wait db-instance-available --db-instance-identifier pg-demo
aws ec2 wait instance-running --instance-ids "$(terraform output -raw bastion_id)"
# the SSM agent needs another minute; the tunnel works once this prints "Online"
aws ssm describe-instance-information --query 'InstanceInformationList[].PingStatus' --output text
```

After a start the cache is cold: open the tunnel and run `\i sql/00b_reset.sql` once (it prewarms
the tables) before rehearsing or going on stage. Stopping from the CLI does not confuse Terraform:
`terraform destroy` after the talk works the same.

## Order on stage

Open a shell into psql: `docker compose exec db psql -U postgres`, then `\i /demo/<file>`.
Better on a projector: open each file in an editor and run the statements one at a time.

Planned for a 60-minute talk: six live demos (about 25 minutes). "Talk" means the slide already
shows the measured result; the script is there for rehearsal or Q&A.

| Slide | File | On stage | What the audience sees |
|---|---|---|---|
| 4-5 | `01_cast.sql` (first two queries) | **Live** | `created_at::date = ...` Seq Scan ~1.3 s, "Rows Removed by Filter" ~10M; the range version uses `idx_orders_created` in ~20 ms |
| 6 | `01_cast.sql` (rest) | Talk | `lower(email)`, `id = 123.0`, `LIKE '%...'` and their fixes |
| 8 | `02b_write_cost_optional.sql` | Talk | Insert 1M rows: ~1.4 s with no index vs ~19 s with five indexes |
| 8-9 | `02_selectivity_optional.sql` | Talk | `pg_stats` most_common_vals; `refunded` uses the index, `completed` does a Seq Scan; unused indexes |
| 10 | `02c_stale_stats.sql` | **Live** | Bulk load without ANALYZE: estimate `rows=1`, actual 500,000 -> Nested Loop, ~4.7 s. `ANALYZE` -> Hash Join, ~1.3 s |
| 11 | `03_composite_optional.sql` | Talk | `(customer_id, created_at)` index used for the first two queries; Seq Scan when only `created_at` is filtered |
| 13, 16 | `04_covering.sql` | **Live** | Index Only Scan with `Heap Fetches: 0`; bulk UPDATE -> `Heap Fetches: ~20000`; VACUUM -> back to 0 |
| 14 | `05_partial_optional.sql` | Talk | Size: full index 214 MB vs partial 2.2 MB; used only when the query has `status = 'pending'` |
| 15 | `05b_brin.sql` | **Live** | BRIN 40 kB vs B-tree 214 MB. On `orders` (correlation 0) BRIN reads every block (lossy=84,558), ~1.3 s; on `orders_by_time` (correlation 1) it reads 256 blocks, ~6 ms |
| 17 | `06_mvcc_optional.sql` | Optional | xmin/xmax/ctid before and after UPDATE; old tuple in the page with `t_xmax` set |
| 18-19 | `07_bloat_vacuum.sql` | **Live** | 1M-row copy: 66 MB -> 130 MB -> 195 MB; VACUUM: still 195 MB; next UPDATE reuses space; VACUUM FULL -> 65 MB |
| 20 | `08_long_transaction_optional.sql` | Talk | Two terminals. VACUUM VERBOSE: "100000 are dead but not yet removable" until session A commits |
| 22 | `09_pg_stat_statements.sql` | **Live** | Top queries by total time: the demos you just ran |
| 23 | `sql/pi/load.sh lock` + `10_wait_events_optional.sql` (RDS only) | Optional | Performance Insights: `Lock:tuple` / `Lock:transactionid`. All three phases take ~5 min |

Order matters: `08` needs the table from `07`. `04` works with or without `03`.
To start over, run `00b_reset.sql` (a few seconds): it drops the demo indexes and tables, undoes the
`04`/`06` updates, vacuums, resets `pg_stat_statements` and index stats, and prewarms the cache.
Run it after each rehearsal and right before the talk. `00_setup.sql` rebuilds everything from scratch
(it also builds `orders_by_time`, the time-ordered copy used by `05b_brin.sql`).

## Performance Insights demo (RDS only, optional)

Shows *what sessions wait on*, the RDS view of `pg_stat_activity`. Open the RDS console ->
`pg-demo` -> Monitoring -> Database Insights / Performance Insights, "DB load" sliced by wait events,
last 15 minutes. Then generate load (tunnel must be open):

```bash
sql/pi/load.sh            # cpu -> lock -> io, 60 s each, 30 s pause between
sql/pi/load.sh lock       # or one phase at a time while you talk
```

| Phase | Load | What the chart shows |
|---|---|---|
| `cpu` | 6 sessions run the slide-4 Seq Scan on 2 vCPUs | Green CPU band at ~6, above the "Max vCPU" line at 2: queries are queuing for CPU |
| `lock` | 1 session holds row `id = 1`, 4 sessions try to update it | `Lock:tuple` + `Lock:transactionid` (the queue) and `Timeout:PgSleep` (the holder) |
| `io` | 8 sessions commit one row at a time | `LWLock:WALWrite` + `IO:WALSync`: every COMMIT waits for a WAL flush. Fix: batch commits |

In a second psql, `\i sql/10_wait_events_optional.sql` shows the same thing live, once per second (that is
exactly what Performance Insights samples). Below the chart, "Top SQL" lists the queries behind
each wait, which ties back to `pg_stat_statements` on slide 22.
Run `00b_reset.sql` afterwards (the lock and io phases write to `orders.note`).

## Notes

- Each EXPLAIN script sets `max_parallel_workers_per_gather = 0` and `jit = off` so plans stay short on screen.
- The range query shows as **Bitmap Heap Scan + Bitmap Index Scan** (about 14k matching rows); the slide matches this.
- Times are from a 2-core test machine; a laptop will differ, but the ratios hold.
- Before going on stage, run each script once so the data is in cache and the first demo is not slower than the rest.
