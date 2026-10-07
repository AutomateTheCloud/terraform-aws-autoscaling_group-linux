# Automate the Cloud Terraform modules: working rules

This file is the same in every Automate the Cloud Terraform module repository.
Change it in one place and copy it to the others; do not let copies drift. The
reference implementation of everything below is
[terraform-aws-s3_bucket](https://github.com/AutomateTheCloud/terraform-aws-s3_bucket).

These modules are published on the Terraform Registry under `AutomateTheCloud`.
Automate the Cloud Inc. is a Kentucky 501(c)(3) that teaches cloud
infrastructure, and the modules are teaching material as well as tools: people
read them to learn, copy examples out of them, and build real infrastructure on
them. Correctness, secure defaults, and clear documentation matter more than
features.

## Ground rules

- Do not commit, push, tag, or change repository settings unless asked.
- Commit messages and pull requests describe the change only. Never mention an
  AI tool or add attribution trailers for one.
- Sign off every commit with `git commit -s` (Developer Certificate of Origin).
- Say what you verified and how. "Tests pass" means you ran them; otherwise say
  it is untested.

## Versions

- Each module has its own semantic version, from git tags (`v1.0.0`),
  independent of the Terraform version and of other modules.
- `versions.tf` sets minimums only, never an upper bound: `required_version =
  ">= 1.9"`, and each provider at the oldest version the code actually needs
  (`hashicorp/aws >= 6.0`). Examples are root modules and pin with `~>`.
- Test on the oldest supported versions and the newest. Use tfswitch to install
  Terraform versions.

## Module design

- **Provider:** use the default `aws` provider, and pass `region = var.region`
  to every resource and data source that accepts it (`region` defaults to
  `null`, meaning the provider's Region). Use `configuration_aliases` only for a
  module that truly works across two accounts or Regions at once.
- **`details`:** every module takes the same required `details` input (`scope`,
  `purpose`, `environment`, optional `*_abbr` and `additional_tags`). It tags
  every resource and produces the `abbr` and `machine` name forms. Copy its
  type, validation and locals from the reference module unchanged.
- **One output, `metadata`:** `details`, `aws` (account, Region name, `abbr`,
  description), and one entry per resource, `null` when not created. It depends
  on every resource in the module, so two module calls whose inputs read each
  other's `metadata` (two security groups whose rules name each other) form a
  cycle. Where callers will do that, say so in the README and show the fix in an
  example: create one side outside the module calls.
- **Typed inputs:** `object({...})` with `optional()` defaults, never `any`.
  `nullable = false` where there is a default. Required inputs have no default
  and `nullable = false` too: a nullable required input accepts `null`, which
  skips a check such as `var.name != ""` and reaches the provider.
- **Validations:** add a `validation` block for any value AWS would reject, so
  mistakes fail at plan time with a clear message. Encode what the API **and**
  the provider at its floor accept, probed with the AWS CLI: AWS documentation
  can be stricter or looser than the API, and the provider can be stricter than
  both. Say in the description when the provider, not AWS, sets the limit.
- **Secure defaults:** a resource created with only the required inputs is
  private, encrypted, and least-privilege. Anything public or broader is an
  explicit opt-in. A secure default can rule out another feature (RDS refuses a
  read replica of a database whose password it manages): read the AWS
  documentation's limitations for each one, and test every feature with it.
- **No broad presets:** do not add switches that grant many services or
  accounts access at once. Give a general escape hatch (such as
  `source_policy_documents`) and an example that shows a narrowly scoped grant.
- **Grants that reach further than they look:**
  - `Principal = "*"` with an `aws:PrincipalOrgID` condition lets every role
    and user in the resource's own account use it with no IAM policy of their
    own; only other accounts also need one. Say so in the input's description.
  - `kms:Decrypt` limited by `kms:ViaService` covers everything that service
    encrypts with the key. When the module means only some of it, also
    condition on the service's encryption context, such as
    `kms:EncryptionContext:PARAMETER_ARN` for Parameter Store, and test a
    denied case.
- **Log groups a service writes to** (RDS, Redshift audit logs) are created by
  the module, with a retention input, before the resource that writes to them
  (`depends_on`). Otherwise the service creates them itself, outside Terraform,
  with events kept forever.
- **A setting that tells AWS about another resource**, such as an ECS cluster's
  `cloud_watch_encryption_enabled` for its log group, is computed from the input
  that makes it true, never hard-coded. AWS accepts a false claim at create and
  fails only when the feature is used.
- **`count` and `for_each` depend on inputs only**, never on values known only
  after apply, so a dependency created in the same run still plans.
- **Do not look up inputs with data sources.** The caller may create the thing
  in the same run, and Terraform can read the data source at plan time, before
  it exists. Take IDs as inputs (subnet IDs, route table IDs, not a tag to
  search by) and build what you need from them.
- **No hard-coded per-Region tables.** Use service principals, provider data
  sources, or a computed value with a small override map. Build ARNs from
  resource attributes, never `arn:aws:` strings, so GovCloud and China work.
- **Never set a ForceNew attribute that a user might toggle later** on a
  stateful resource; find the separate resource that does it in place.
- **No `null_resource` for input checks**; use `validation` blocks.
- **Avoid `local-exec`.** A command needs its CLI on every machine that runs
  Terraform, and uses that CLI's credentials, not the provider's `profile` or
  `assume_role`. Use it only when no provider resource can make the change,
  after asking the maintainers, and say so in the README. Put it in a
  `terraform_data` resource with every ID it acts on in `triggers_replace` and
  the commands in `input`, so the destroy-time command acts on what the
  create-time one did.

## Replacements

Mocked plans never show a replacement, so check each of these with a real plan.

- **A resource that a change replaces, whose ID other resources use**, gets
  `lifecycle { create_before_destroy = true }` when two can exist at once, so
  they move to the new one in place instead of being removed first.
- **`create_before_destroy` needs a new name** for the new object. Use it only
  with `name_prefix` or a name that changes with every replacing input. A
  tainted resource, such as one whose create failed, is replaced too, and a
  fixed name then collides with the old one.
- **Resources that hang off a replaced resource** (its security group rules,
  log groups named after it) are replaced too, and by default the old ones are
  deleted first. Give them `create_before_destroy` as well, and make the
  resource that uses them `depends_on` them, so the old ones go only after it
  has moved. Keep the values they need known from the inputs, or `depends_on`
  makes a cycle.
- **Computed attributes of a replaced resource are unknown at plan.** Resources
  built from them are replaced too, if those arguments force replacement. If
  the values cannot change, use `ignore_changes`.
- **A child that refers to its parent by name**, such as a Redshift Serverless
  workgroup's `namespace_name`, is not replaced with the parent, and AWS refuses
  to delete a parent that still has the child. Give the child
  `replace_triggered_by` on a parent attribute that changes only when the parent
  is created again, such as `namespace_id`.
- **An update the provider plans in place that AWS cannot make** needs a
  replacement: hold the input in a `terraform_data` resource and give the
  resource `replace_triggered_by = [terraform_data.x]`.
- **Final snapshot names with a random suffix** need every input that replaces
  the resource in the `random_id`'s `keepers`, not only the name. Otherwise the
  replacement keeps the suffix, the old resource's final snapshot takes the
  name, and the next delete fails because the snapshot exists.
- **A parent that refuses to be deleted** (deletion protection, or something
  from another configuration still in it) protects only itself. Terraform
  deletes its dependents first, then fails on the parent. Say so in the input's
  description and the README.

## Every apply must plan clean

The plan after an apply must show no changes, with only the required inputs and
with most options on, on the oldest and newest provider. These causes have all
been seen in AWS, and mocked tests show none of them:

- **Empty values:** an optional list, set or map passed as `null`, and
  sometimes even as `[]`, can be saved as `null` and read back as `[]` or `{}`.
  Pass the empty value, and if that is refused or does not help, leave the
  attribute out of `metadata`.
- **Attributes another resource fills in:** a security group's `ingress` and
  `egress` with separate rule resources, an Elastic IP address's association
  attributes, an SQS queue's `policy`, a RAM share's `permission_arns`, an
  Aurora cluster's `cluster_members`. Leave them out of `metadata` and output
  the attaching resource instead.
- **Values AWS rewrites:** send values in the form AWS returns them (lowercase
  listener protocols, network addresses without host bits).
- **Defaults that differ:** when AWS's default differs from the provider's (AWS
  now turns on Redshift AZ relocation; provider 6.0.0 sends it only when true),
  set the argument explicitly.
- **Parameter groups:** removing a `parameter` does not reset it in AWS, and
  every plan tries to remove it again. A parameter the module sets in one mode
  is set in every mode, to its default when off.
- **Optional and computed blocks read back in full,** such as a Redshift
  Serverless workgroup's `config_parameter` on the provider floor: send the
  whole set, AWS's defaults merged under the caller's values.
- **Arguments the provider declares as conflicting:** leave the unused one
  `null`; even `false` or `""` is refused. After switching between them, or
  removing an optional argument, the first plan can show only `metadata`
  changing. Document it: a plain `terraform apply` clears it. Do not suggest
  `apply -refresh-only` for that case: Terraform 1.9.8 refuses a refresh-only
  plan whose only changes are outputs.
- **IAM roles created in the same apply** can be saved in a policy by unique ID
  (`AROA...`) before IAM resolves the ARN, so the next plan shows a change.
  `terraform apply -refresh-only` clears it; document it where it can happen.

## Outputs must not warn

List output attributes one by one. Referencing a whole resource, or iterating
over one with `for`, also references its deprecated and sensitive attributes,
and every caller's plan then prints deprecation warnings or the output becomes
sensitive. Generate the attribute list from `terraform providers schema -json`:
keep an attribute only if it exists at the provider floor and is not deprecated
in the latest release. CI fails on any `terraform validate` warning.

## Files and layout

`versions.tf`, `main.tf` (data sources, locals), `variables.tf` (every
variable, alphabetical), `outputs.tf`, `locals.tf`, one file per resource type,
`tests/`, `examples/<name>/` each with a README. Also, copied from the
reference module and adapted: `.terraform-docs.yml`, `.tflint.hcl`,
`.trivyignore.yaml`, `.github/` (CI workflow, CODEOWNERS, pull request
template, Dependabot), `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md`,
`AUTHORS.md`, `LICENSE`, `NOTICE`.

## Documentation

- Variable and output descriptions are the reference documentation:
  terraform-docs generates the README's Reference section from them. Describe
  every attribute and its default, with a blank line before each list. Run
  `terraform-docs .` after changing any variable or output; CI checks it.
- The README's hand-written part: what the module creates, a table of
  defaults, usage with the registry source and `version = "~> 1.0"`, the
  `details` section, examples, "Things to know", contributing, testing,
  license.
- Links in anything the registry shows (README, CHANGELOG, example READMEs,
  descriptions) are full GitHub URLs to `main`; the registry does not resolve
  relative links.
- A statement about how AWS or the provider behaves (what happens on delete,
  what a default is, what is accepted) is checked in a real account before it
  is published, or worded as AWS documentation's claim with a link.
- When the module sets a default that AWS copies into resources the caller
  manages (an ECS cluster's default capacity provider strategy, copied into a
  service that names none), say in the README what the caller's resources must
  set to plan clean.
- Examples must make sense on their own and be safe to apply. One purpose per
  example. Apply every example in a real account before release. Never put
  `depends_on` on a module call: Terraform then reads the module's data sources
  at apply time and can replace its resources; pass an attribute into an input
  instead. Public hosted zones use `.test` names; AWS rejects `example.com` as
  reserved.
- Voice: plain and specific. Say what a thing does before why. Short sentences,
  no marketing words, expand an acronym the first time it appears, link text
  that makes sense out of context. "Automate the Cloud" in prose, "Automate the
  Cloud Inc." in legal text. American English everywhere.
- A refreshed module is published as new: `CHANGELOG.md` starts with a 1.0.0
  initial-release entry and does not mention earlier versions.

## Licensing

Terraform modules are code only, under the Apache License 2.0:

- `LICENSE`: the official Apache 2.0 text, byte for byte. Download it; never
  retype it.
- `NOTICE`: `Automate the Cloud Inc.` and `Copyright <YEAR> Automate the Cloud Inc.`
- Every source file (`.tf`, `.tftest.hcl`, `.hcl`, workflow YAML) starts with:

  ```hcl
  # Copyright <YEAR> Automate the Cloud Inc.
  # SPDX-License-Identifier: Apache-2.0
  ```

- `<YEAR>` is the year the module was rebuilt and released as 1.0.0 (2026 for
  every module refreshed in 2026), in `NOTICE` and every header alike.
- The README's license section says the code is Apache 2.0 and that the name
  and logo are not licensed.

The full policy is the organization's licensing playbook. Read it before any
licensing change, and report rather than decide: an earlier license, unclear
ownership, third-party material, or personal information in files or history.

## Testing

- `tests/` holds offline `terraform test` files with mocked providers. Every
  bug fix and every feature gets a test. Assert on configured values in `plan`
  runs; mocks leave computed values unknown at plan, so use `apply` (still
  mocked) for those, and `plan` for `expect_failures`.
- Mocks are not the provider. They do not apply the provider's defaults (an
  argument left `null` plans as `null`), never plan a replacement, and skip
  plan-time checks between arguments that newer providers make in code. They
  do run the checks in the provider's schema (ranges, conflicting arguments),
  which can differ by version: use values the floor accepts, and run the tests
  on the floor before the first real apply.
- The runs in one `.tftest.hcl` file share one state: a `plan` after an `apply`
  plans against what that apply created. Put runs that assume a fresh resource
  before the first `apply`, or in their own file.
- To assert on a list or set of nested blocks, compare a projection such as
  `toset([for t in r.target_ip : "${t.ip}|${t.port}"])`. A literal whose
  elements all have `null` in one attribute has a different type, and the
  assertion fails even though the values match.
- `apply` runs execute provisioners, even with every provider mocked and with
  `override_resource`. Turn `local-exec` resources off in `apply` runs, and
  assert on their `input` in a `plan` run instead.
- CI runs fmt, terraform-docs, TFLint, Trivy, and the tests on the oldest and
  newest Terraform and provider versions, plus a DCO sign-off check.
- Before a release, verify in a real AWS account, never making anything public
  in a shared account:
  - a fresh apply with only the required inputs, one with most options on, and
    one on the provider floor, each followed by a re-plan with no changes;
  - each updatable input changed on its own, then re-planned and checked with
    the AWS CLI. The provider can plan an update that AWS ignores or refuses,
    and after a failed apply it can save values it never set, so the next plan
    shows no changes. A setting turned off and on again can come back without
    its options;
  - each feature used, not only created: traffic through a load balancer from
    another host, a session through ECS Exec, a `COPY` through the role;
  - a destroy, checking the order, then confirm nothing is left.

## Terraform traps that have already bitten

- `cond ? [ {...} ] : []` fails when the objects differ in shape; use
  `[for s in [ {...} ] : s if cond]`.
- `tolist()` fails on a JSON array of differently shaped objects; test with
  `can(x[0])`.
- `coalesce()` errors when every argument is null or empty.
- Typed objects reject a missing required attribute but silently drop a
  misspelled optional one, so document attribute names exactly.
- A `for` expression carries the deprecated and sensitive marks of everything
  it iterates over.
- Anything computed from a `sensitive` variable is sensitive too, even
  `var.password == null`, and one such attribute makes `metadata` sensitive.
  When only whether the input is set matters, use
  `nonsensitive(var.password == null)`, and test with a sensitive value.
- Terraform 1.9 evaluates both sides of `&&` and `||`. `x == null || x > 0`
  fails for a null `x`, and `true || <unknown>` is unknown, which breaks a
  `count`. Use a conditional, which is evaluated lazily:
  `x == null ? true : x > 0`. Run the tests on 1.9 before a release.
- A `validation` that reads a local built from two variables, each validated
  through it, is a cycle. Put the expression in each variable's own validation.
- New deprecations appear first on the newest Terraform and provider. Run
  `terraform validate` there before every release.
- `x != null` on a value from a resource created in the same run is unknown
  at plan, so it cannot decide `count` or `for_each`. Take such a value inside
  an object input (`{ zone_id = ... }`): whether the object is `null` is known.
- Some provider operations retry every error, so a change AWS refuses, or
  throttles, runs silently until the timeout. Make the same call with the AWS
  CLI to see the error, stop Terraform with one Ctrl-C so it saves the state,
  and document the case.
- Sibling resources split out of one AWS resource (a DynamoDB table's
  `aws_dynamodb_global_secondary_index`) are created and deleted in parallel,
  and AWS may accept one change at a time. Test two or more in one apply and
  one destroy, and document `-parallelism=1` if they fail.
- `terraform validate` fails on a module that declares
  `configuration_aliases`. CI writes a non-empty provider block for each alias
  (an empty one is a deprecated proxy block) and runs `validate -no-tests`,
  because test fixtures that pass the alias in clash with that block.
