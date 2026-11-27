# Run store

Every submitted forecast writes one immutable JSON record (`lib/run_record.rb`)
for later analysis and a future front end. CI uploads it to S3.

## Layout

```
runs/{post_id}/{YYYYMMDDTHHMMSSZ}-{github_run_id}-{attempt}.json
```

- Append-only: a key is written once and never rewritten, so parallel jobs
  never conflict and the layout copies unchanged to another backend
  (`aws s3 sync`, a git branch, a local directory).
- Resolutions and scores arrive later and belong under a separate prefix
  (e.g. `resolutions/{post_id}.json`) rather than edits to run records.
- Readers branch on `schema_version`; old records are never rewritten.

## Record contents (schema_version 1)

| Field | Contents |
|---|---|
| `post_id`, `question_id`, `title`, `type`, `test_question` | Identity |
| `recorded_at`, `run`, `prompt_version` | When, which CI run and commit, which prompts |
| `question` | Full Metaculus post at forecast time, including the community aggregate |
| `news` | `summary` (news_summary.md) and `items` (news.json) |
| `research` | Raw research response |
| `stages.forecast`, `stages.revision` | Raw response per forecaster, plus parsed `value` |
| `stages.consensus` | Raw consensus response, plus parsed `value` |
| `mechanical_baseline` | Pooled baseline text shown to consensus |
| `submission` | Payload posted to Metaculus and the comment text |

Raw responses keep `model`, the serving host (`provider`), `usage` (tokens and
cost) and `prompt_version`. `value` is a probability (binary), percentile →
value map with string keys (numeric/discrete), or option → probability map
(multiple choice); `null` if it couldn't be parsed.

Locally, records land in `tmp/run_store/` (override with `RUN_STORE_DIR`).

## AWS setup

CI authenticates with GitHub OIDC, so there are no stored AWS keys. Until the
repository variables below are set, the upload is skipped and records are
kept only as short-lived Actions artifacts (`{post_id}.run_record`).

1. **Bucket**: create a private bucket (block all public access) and turn on
   versioning.
2. **OIDC provider**: in IAM, add an identity provider of type OpenID Connect
   with URL `https://token.actions.githubusercontent.com` and audience
   `sts.amazonaws.com` (skip if the account already has it).
3. **Role** with this trust policy (it only trusts this repository's `main` branch):

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com" },
       "Action": "sts:AssumeRoleWithWebIdentity",
       "Condition": {
         "StringEquals": {
           "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
           "token.actions.githubusercontent.com:sub": "repo:geemus/metaculus-ai-forecasting:ref:refs/heads/main"
         }
       }
     }]
   }
   ```

   and this permissions policy (write-only to the record prefixes, no delete):

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Action": "s3:PutObject",
       "Resource": ["arn:aws:s3:::<BUCKET>/runs/*", "arn:aws:s3:::<BUCKET>/resolutions/*"]
     }]
   }
   ```

   Reading jobs added later (resolution backfill, front-end build) need
   `s3:GetObject` and `s3:ListBucket` on the bucket. Give them a separate role
   or extend this one.
4. **Repository variables** (Settings → Secrets and variables → Actions →
   Variables): `RUN_STORE_BUCKET`, `RUN_STORE_ROLE_ARN`, and optionally
   `RUN_STORE_REGION` (default `us-east-1`).

## Reading records

```bash
aws s3 sync s3://<BUCKET>/runs ./store/runs
duckdb -c "select post_id, type, prompt_version, stages.consensus.value
           from read_json_auto('store/runs/**/*.json')"
```

or in Ruby: `RunStore.new(root: './store').list('runs/')`.
