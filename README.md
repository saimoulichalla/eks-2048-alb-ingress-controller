# 🎮 2048 Game Deployment on AWS EKS with ALB Ingress Controller & IRSA

> A production-style Kubernetes project deploying the 2048 game on AWS EKS using Fargate, AWS Application Load Balancer (ALB) Ingress Controller, and IRSA (IAM Roles for Service Accounts) for least-privilege IAM access.

---

## 🏗️ Architecture Overview

```
User Request
     │
     ▼
AWS Application Load Balancer (ALB)
     │   ← Created & managed by ALB Controller
     ▼
Kubernetes Ingress Resource (game-2048 namespace)
     │
     ▼
Kubernetes Service
     │
     ▼
Pod (2048 Game App) — running on AWS Fargate
     
ALB Controller Pod (kube-system namespace)
     │
     │ ← Assumes IAM Role via IRSA (Service Account + OIDC)
     ▼
AWS IAM → ELB, EC2, Target Groups
```

---

## 🔐 Why IRSA? (Key Concept)

Traditional approach: Attach IAM permissions to the **EC2 worker node IAM role** — but this gives ALL pods on that node the same permissions, violating the **principle of least privilege**.

**IRSA (IAM Roles for Service Accounts)** solves this by:

1. Creating a **Kubernetes Service Account**
2. Creating an **IAM Role** with only the required permissions
3. Establishing an **IAM OIDC Provider** trust relationship between AWS IAM and the EKS cluster

Result: Only the **ALB Controller Pod** (using that specific Service Account) can assume the IAM Role and get temporary AWS credentials via **AWS STS**. All other pods remain isolated and secure.

---

## 🛠️ Tech Stack

| Layer | Tool |
|---|---|
| Cloud | AWS (EKS, IAM, ALB, VPC, Fargate) |
| Container Orchestration | Kubernetes (EKS) |
| Worker Nodes | AWS Fargate (serverless) |
| Ingress Controller | AWS Load Balancer Controller |
| IAM Integration | IRSA + IAM OIDC Provider |
| Package Manager | Helm |
| CLI Tools | kubectl, eksctl, AWS CLI |

---

## ✅ Prerequisites

Install the following tools locally:

```bash
# 1. AWS CLI
# Download from: https://aws.amazon.com/cli/

# 2. kubectl
# Download from: https://kubernetes.io/docs/tasks/tools/

# 3. eksctl
# Download from: https://eksctl.io/
# Place the .exe in C:\windows\system32 (Windows)

# Configure AWS credentials
aws configure
# Enter: Access Key ID, Secret Access Key, Region
```

---

## 🚀 Step-by-Step Setup

### Step 1 — Create EKS Cluster with Fargate

```bash
eksctl create cluster \
  --name demo-cluster \
  --region us-east-1 \
  --fargate
```

> This automatically creates a VPC with public and private subnets, sets up the EKS control plane, installs add-ons (VPC-CNI, CoreDNS, kube-proxy), and creates a default Fargate profile. Takes 10–20 minutes.

---

### Step 2 — Configure kubectl for EKS

```bash
aws eks update-kubeconfig --name demo-cluster --region us-east-1

# Verify
kubectl get nodes
```

---

### Step 3 — Create Fargate Profile for App Namespace

Fargate profiles define which namespaces can run pods on Fargate. We need a separate profile for our `game-2048` namespace:

```bash
eksctl create fargateprofile \
  --cluster demo-cluster \
  --region us-east-1 \
  --name alb-sample-app \
  --namespace game-2048
```

---

### Step 4 — Deploy the 2048 Game

This single YAML deploys all required resources: Namespace, Deployment, Service, and Ingress:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.5.4/docs/examples/2048/2048_full.yaml
```

Verify resources:

```bash
kubectl get all -n game-2048
kubectl get ingress -n game-2048
```

> At this point, the Ingress will have **no address** — because there's no Ingress Controller yet. We set that up next.

---

### Step 5 — Associate IAM OIDC Provider

The ALB Controller pod needs to talk to AWS. For that, we set up an OIDC trust relationship:

```bash
eksctl utils associate-iam-oidc-provider \
  --cluster demo-cluster \
  --approve
```

---

### Step 6 — Create IAM Policy for ALB Controller

```bash
# Download the policy JSON provided by the ALB controller project
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.11.0/docs/install/iam_policy.json

# Create the IAM policy in AWS
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json
```

This policy grants permissions to create/manage: ELB, Security Groups, and Target Groups.

---

### Step 7 — Create Service Account with IRSA

This single command creates both the IAM Role and the Kubernetes Service Account, and links them together (IRSA):

```bash
eksctl create iamserviceaccount \
  --cluster=demo-cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::<your-aws-account-id>:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve
```

---

### Step 8 — Install ALB Controller via Helm

```bash
# Add the EKS Helm repo
helm repo add eks https://aws.github.io/eks-charts

# Update the repo
helm repo update eks

# Install the ALB Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=demo-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=us-east-1 \
  --set vpcId=<your-vpc-id>
```

> Get your VPC ID from: AWS Console → EKS → Your Cluster → Networking tab

---

### Step 9 — Verify & Access the App

```bash
# Verify ALB Controller is running
kubectl get deployment -n kube-system aws-load-balancer-controller

# Get the ALB address (takes 2-3 mins to provision)
kubectl get ingress -n game-2048
```

Once the address appears, open it in your browser — the 2048 game will be live! 🎮

---

## 🧹 Cleanup

```bash
# Delete the EKS cluster and all associated resources
eksctl delete cluster --name demo-cluster --region us-east-1
```

---

## 📁 Project Structure

```
eks-2048-game-alb-controller/
├── k8s/
│   └── 2048_full.yaml          # Namespace, Deployment, Service, Ingress
├── iam/
│   └── iam_policy.json         # IAM policy for ALB Controller
├── docs/
│   └── setup-notes.md          # Detailed project notes
└── README.md
```

---

## 🔗 Links

- 💼 **LinkedIn:** [linkedin.com/in/sai-mouli](https://www.linkedin.com/in/sai-mouli/)
- 🐙 **GitHub:** [github.com/saimoulichalla](https://github.com/saimoulichalla)

---

<p align="center">Built on AWS EKS ☁️ | Secured with IRSA 🔐 | Managed by Helm ⎈</p>
