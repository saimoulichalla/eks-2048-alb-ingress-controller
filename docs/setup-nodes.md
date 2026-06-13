# EKS Project — Setup Notes & Learnings

> Personal notes from end-to-end deployment of the 2048 game on AWS EKS with ALB Ingress Controller and IRSA.

---

## Tools & Prerequisites

| Tool | Purpose |
|---|---|
| `kubectl` | Kubernetes CLI to interact with the EKS cluster |
| `eksctl` | CLI to create and manage EKS clusters |
| `AWS CLI` | Configure AWS credentials and interact with AWS services |
| `Helm` | Package manager for installing Kubernetes applications |

**AWS CLI configuration requires:**
- Access Key ID
- Secret Access Key
- Default Region

> For demos, root account was used to avoid permission issues. In production, always use IAM users/roles with least privilege.

---

## EKS Cluster — What eksctl Does Automatically

When we run `eksctl create cluster`:
- Uses the specified region and sets up Availability Zones
- Creates a VPC with **public and private subnets** inside those AZs
- Deploys the EKS control plane (managed by AWS)
- Installs EKS add-ons: `VPC-CNI`, `kube-proxy`, `CoreDNS`, `metrics-server`
- Creates a default **Fargate profile** (`fp-default`) covering `default` and `kube-system` namespaces

> Cluster creation takes 10–20 minutes. Be patient.

---

## EKS Console Features

After cluster creation, the AWS Console (EKS → Cluster → Resources) provides:
- Kubernetes version info
- Resource viewer (pods, daemonsets, service accounts) — without needing kubectl
- Acts like a built-in Kubernetes dashboard

---

## Fargate Profiles — Important Note

Fargate profiles define **which namespaces** can run pods on Fargate.

- Default profile covers: `default` and `kube-system`
- For custom namespaces (e.g. `game-2048`), a **new Fargate profile must be created**
- This is unique to Fargate — EC2 worker nodes don't need this step

---

## kubectl + EKS Configuration

Instead of using the AWS Console UI to check pods/deployments, we can use `kubectl` locally.

To configure kubectl to talk to our EKS cluster:
```bash
aws eks update-kubeconfig --name <cluster-name> --region <region>
```

Then verify:
```bash
kubectl get nodes
```

---

## 2048 App Deployment — Single YAML

The single manifest file creates 4 resources at once:
1. **Namespace** — `game-2048`
2. **Deployment** — runs the 2048 game pod (Docker image pulled from ECR public registry)
3. **Service** — exposes the pod internally
4. **Ingress** — defines routing rules for external access

After applying:
```bash
kubectl get ingress -n game-2048
```
→ **No ADDRESS** shown yet — because there's no Ingress Controller installed. The Ingress resource is just a definition; it needs a controller to act on it.

---

## Why No Address on Ingress Initially?

An Ingress resource alone does nothing. It needs an **Ingress Controller** — a pod that:
1. Watches for Ingress resources in the cluster
2. Reads the routing rules defined in them
3. Creates and configures the actual AWS ALB (listeners, target groups, security groups)

Without the controller, the Ingress is just an ignored config file.

---

## IAM OIDC Provider — Why It's Needed

The ALB Controller is a Kubernetes pod. It needs to **call AWS APIs** (to create ALBs, target groups, etc.). For that, it needs IAM permissions.

**OIDC (OpenID Connect)** is the trust mechanism that allows AWS IAM to trust identities coming from the EKS cluster.

Real-world analogy: When you sign into a website using Google — Google is the identity provider (OIDC provider). AWS IAM trusts the EKS cluster the same way.

```bash
eksctl utils associate-iam-oidc-provider --cluster <name> --approve
```

---

## IRSA — IAM Roles for Service Accounts

### Old approach (not recommended):
Attach IAM permissions to the **EC2 worker node IAM role** → All pods on that node inherit the same permissions → Violates least privilege.

### IRSA approach:
1. Create a **Kubernetes Service Account**
2. Create an **IAM Role** with required permissions
3. Link them via the **OIDC trust relationship**

Result: Only pods using that specific Service Account can assume the IAM Role and get **temporary credentials via AWS STS**.

```bash
eksctl create iamserviceaccount \
  --cluster=<cluster> \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::<account-id>:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve
```

> This single command creates both the IAM Role and the K8s Service Account and links them together.

---

## Helm — What It Does Here

Helm is a **package manager for Kubernetes** — similar to `apt` for Ubuntu or `npm` for Node.js.

- Helm **charts** are pre-packaged Kubernetes application templates
- We add the EKS Helm repo (like adding a software repository)
- Then install the ALB Controller chart from it

```bash
helm repo add eks https://aws.github.io/eks-charts   # Add repo
helm repo update eks                                   # Update (like apt update)
helm install aws-load-balancer-controller ...          # Install the chart
```

The Helm chart deploys **2 replicas** of the ALB Controller pod for high availability.

---

## What Happens After ALB Controller is Installed?

The ALB Controller pod continuously **watches** for Kubernetes Ingress resources. When it detects one configured for ALB, it automatically:

1. Creates an **AWS Application Load Balancer**
2. Configures **Listeners** (ports)
3. Creates **Target Groups** (pointing to the pods)
4. Sets up **Security Groups**

After a couple of minutes:
```bash
kubectl get ingress -n game-2048
```
→ Now shows the **ALB DNS address** — open it in browser to access the 2048 game!

---

## Key Observations

- `eksctl create iamserviceaccount` creates the IAM Role automatically — no need to create it separately
- VPC ID is needed during Helm install — get it from EKS Console → Networking tab
- ALB takes 2–3 minutes to provision after the controller detects the Ingress
- Always **delete the cluster** after demo to avoid unexpected AWS charges

---

## Overall Architecture (Mental Model)

```
Pod (ALB Controller)
  └── Uses K8s Service Account
        └── Linked to IAM Role via IRSA + OIDC
              └── Assumes role via AWS STS (temporary credentials)
                    └── Calls AWS APIs → Creates ALB
```

---

*Notes by Sai Mouli | [linkedin.com/in/sai-mouli](https://www.linkedin.com/in/sai-mouli/)*
