# AWS EC2 CI/CD Pipeline — From Manual Deploy to Automated ECR Releases

> **FR** — Une même application Java déployée sur EC2 quatre fois, avec un niveau d'automatisation croissant à chaque itération : déploiement manuel, provisioning d'infrastructure scripté en CLI, pipeline Jenkins via SSH, puis évolution vers Docker Compose, versioning dynamique et migration du registre vers Amazon ECR.
>
> **EN** — The same Java application deployed to EC2 four times, with increasing automation at each iteration: manual deployment, CLI-scripted infrastructure, a Jenkins SSH pipeline, then an evolution to Docker Compose, dynamic versioning, and a registry migration to Amazon ECR.

![AWS](https://img.shields.io/badge/AWS-EC2%20%7C%20ECR-orange?logo=amazonaws)
![Jenkins](https://img.shields.io/badge/Jenkins-CI%2FCD-red?logo=jenkins)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker)
![Java](https://img.shields.io/badge/Java-17-blue?logo=openjdk)
![Maven](https://img.shields.io/badge/Maven-build-red?logo=apachemaven)
![Spring Boot](https://img.shields.io/badge/Spring%20Boot-3-6DB33F?logo=springboot)

---

## Problem

Automation is a series of deliberate decisions, not a single leap. Going straight from "click through the console" to "full CI/CD with a private registry" skips the reasoning that makes each step necessary: why script the infrastructure before automating the deploy, why a shell script instead of inline SSH commands, why a dynamic image tag instead of a hardcoded one, why migrate off Docker Hub at all. This project keeps every one of those intermediate stages instead of only showing the final state.

## Solution

The same Spring Boot application is deployed to EC2 through four stages, each removing one manual step from the last:

1. **Manual** — console-provisioned EC2, SSH in, `docker run` by hand.
2. **CLI-driven infrastructure** — the same VPC/subnet/IGW/route table/security group/EC2/key pair recreated entirely via the AWS CLI instead of console clicks, plus a first Jenkins multibranch pipeline. The command-by-command walkthrough for this stage lives in a dedicated repo, [aws-cli-fundamentals](https://github.com/m-bengueddache/aws-cli-fundamentals) — this project picks up from there rather than duplicating it.
3. **Automated CD via SSH** — Jenkins builds and pushes the image, then SSHes into EC2 to run it directly.
4. **Compose + dynamic versioning + ECR** — deployment moves to Docker Compose (multi-service: app + Postgres), the image tag is derived from the Maven version instead of hardcoded, and the registry migrates from Docker Hub to Amazon ECR.

This repo picks up the story once the infrastructure exists — its own `Jenkinsfile`/`Dockerfile`/`docker-compose.yaml` implement stages 3-4 (the CD pipeline itself), not stage 2's provisioning.

## Architecture

```mermaid
flowchart TD
    subgraph S1["Stage 1 — Manual"]
        A1[Console: create EC2] --> A2[SSH in] --> A3["docker run (by hand)"]
    end
    subgraph S2["Stage 2 — CLI infra + first pipeline"]
        B1["aws-cli-fundamentals:\nVPC, subnet, IGW,\nroute table, SG, EC2"] --> B2["Jenkins multibranch\npipeline"] --> B3["docker-compose up\nvia SSH"]
    end
    subgraph S3["Stage 3 → 4 — CD evolution"]
        C1["Jenkins: build + push"] --> C2["SSH: docker run"]
        C2 -.evolves to.-> C3["scp + docker-compose"]
        C3 -.evolves to.-> C4["dynamic tag\nvia Maven version"]
        C4 -.evolves to.-> C5["registry: Docker Hub → ECR"]
    end
    S1 -."automate the infra".-> S2
    S2 -."automate the deploy".-> S3
```

## Skills demonstrated

- Recognizing which parts of a deployment to automate first — infrastructure before pipeline, pipeline before registry migration — rather than automating everything at once
- Building a Jenkins CD pipeline against a specific EC2 target via `sshagent`, `scp`, and remote shell execution, understanding exactly what each step buys over the previous one
- Extracting inline shell logic into a standalone, testable script (`server-cmds.sh`) once the inline version becomes hard to read
- Deriving a Docker image tag from the Maven project version (`build-helper:parse-version` + regex extraction) instead of hardcoding it, and guarding against the resulting CI self-trigger loop
- Migrating a container registry (Docker Hub → ECR) mid-project and correctly re-wiring authentication and credentials

## Key technical decisions

| Decision | Why |
|---|---|
| Four kept stages instead of one final pipeline | The reasoning behind each automation step is the point — collapsing them into one Jenkinsfile would hide *why* each change was made. |
| Docker Compose over a single `docker run`, from stage 3 onward | The app needs a database sidecar (Postgres); Compose expresses that as one file instead of two coordinated `docker run` commands. |
| Dynamic image tag from the Maven version, not `latest` | `latest` gives no traceability between a running container and the code that produced it; a version + build number does. |
| Migrating from Docker Hub to ECR | One repository per application, IAM-scoped access, and no dependency on a third-party registry's availability or rate limits. |
| `jenkins@example.com` as the CI commit author | Lets an "ignore committer" branch strategy detect and skip builds triggered by the pipeline's own version-bump commit, avoiding an infinite build loop. |

## Limitations

- Single EC2 instance, no load balancer — a deploy briefly interrupts the running container.
- No automated rollback if the new image fails to start.
- Credentials for EC2 host and ECR registry are referenced as Jenkins credentials in this repo's `Jenkinsfile` (`ecr-registry-url`, `ec2-deploy-host`, `ecr-credentials`, `ec2-server-key`, `git-credentials`) — set these up in Jenkins before running the pipeline; no real infrastructure values are committed here.
- AWS CLI infrastructure provisioning for this project follows the same command sequence documented in [aws-cli-fundamentals](https://github.com/m-bengueddache/aws-cli-fundamentals) rather than duplicating it here — that sequence is run manually, not wrapped in a script.

## Roadmap

- [ ] Add `kubectl`-style rollout verification (health check) after `docker-compose up` before considering the deploy successful
- [ ] Replace the single EC2 target with an Auto Scaling Group behind a load balancer for zero-downtime deploys
- [ ] Provision the EC2 target itself with Terraform instead of the AWS CLI scripts, once the Terraform module is further along

---

## Jenkins Prerequisites

| Credential ID | Type | Usage |
|---|---|---|
| `ecr-registry-url` | Secret text | ECR registry hostname (`<account-id>.dkr.ecr.<region>.amazonaws.com`) |
| `ecr-credentials` | Username/Password | Docker login to ECR (`AWS` / token from `aws ecr get-login-password`) |
| `ec2-deploy-host` | Secret text | SSH target, e.g. `ec2-user@<public-ip>` |
| `ec2-server-key` | SSH Username with Private Key | SSH/SCP access to the EC2 instance |
| `git-credentials` | Username/Password | Push the version-bump commit back to GitHub |

Maven must be configured in Jenkins: **Manage Jenkins → Tools → Maven installations**, name `maven`.

## Project Structure

```
.
├── Jenkinsfile          # Final pipeline: version bump -> build -> push to ECR -> Compose deploy -> commit
├── Dockerfile           # Wildcard *.jar copy, Amazon Corretto 17
├── docker-compose.yaml  # App + Postgres, image/tag parameterized via env vars
├── server-cmds.sh       # Deploy script executed on the EC2 instance
├── pom.xml              # Maven project (Spring Boot 3)
└── src/                 # Java application source
```
