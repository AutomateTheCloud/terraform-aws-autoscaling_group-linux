# Contributing

Contributions are welcome. Every change is reviewed closely before it is merged, because people build real infrastructure on this module, so please expect questions and requests for changes.

## Before you start

Open an issue first and describe what you want to change and why. Agreeing on the approach before you write code saves you time. Small fixes, such as typos in the documentation, can go straight to a pull request.

To report a security problem, do not open an issue. Follow [SECURITY.md](SECURITY.md) instead.

## Making a change

You need Terraform 1.9 or later and [terraform-docs](https://terraform-docs.io).

1. Fork the repository and create a branch.
2. Make the change. Keep to one change per pull request.
3. Add or update a test in `tests/` that shows the change works. The tests use mocked AWS providers and need no AWS account. A change to the commands the instances run at boot also needs a real deployment of each operating system it affects.
4. Run the checks:

   ```shell
   terraform fmt -recursive
   terraform init
   terraform test
   terraform-docs .
   ```

5. Describe the change in `CHANGELOG.md` under "Unreleased".
6. Commit with `git commit -s` (see [Sign your commits](#sign-your-commits)), open a pull request, and fill in the checklist.

CI runs the same checks on the oldest and newest supported versions of Terraform and the AWS provider, and also runs [TFLint](https://github.com/terraform-linters/tflint) and a [Trivy](https://trivy.dev) security scan. To run those yourself: `tflint --init && tflint --recursive`, and `trivy config --ignorefile .trivyignore.yaml .`. A pull request is merged only when they pass and a maintainer has approved it.

## Sign your commits

Every commit in a pull request must be signed off. Signing off means you agree to the [Developer Certificate of Origin](https://developercertificate.org/) (DCO): a short statement that you wrote the change, or otherwise have the right to submit it under this project's license. Code written for an employer may belong to the employer, so check before contributing it.

Sign off by committing with `-s`, which adds a line with the name and email from your Git settings:

```shell
git commit -s -m "Add a lifecycle hook for graceful shutdown"
```

```
Signed-off-by: Jane Developer <jane@example.com>
```

The email in the sign-off must match the commit's author email. A check on each pull request lists any commit that is not signed off. To sign off commits you have already made, run `git rebase --signoff main` and force-push the branch.

## Guidelines

- Secure defaults stay secure. A change must not make instances created with only the required inputs less private or less protected, for example by allowing inbound network access, giving them public addresses, allowing IMDSv1, leaving a volume unencrypted, granting their IAM role broader permissions, or making a load balancer internet-facing by default.
- New inputs need a type, a default where one makes sense, validation for values AWS would reject, and a description that explains every attribute.
- A change that would replace every running instance or the load balancer for existing callers, or make callers change their code, needs a strong reason and a new major version.
- Write in plain, American English, in the same style as the existing documentation.

## License

This module is licensed under the [Apache License 2.0](LICENSE). Under section 5 of that license, any contribution you submit for inclusion is licensed under the same terms. Your sign-off confirms you have the right to submit it.
