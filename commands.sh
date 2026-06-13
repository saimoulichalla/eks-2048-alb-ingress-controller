#!/bin/bash

# =============================================================
# EKS 2048 Game Deployment with ALB Controller & IRSA
# Author: Sai Mouli | github.com/saimoulichalla
# =============================================================

# --------------------------
# VARIABLES — update these before running
# --------------------------
CLUSTER_NAME="demo-cluster"
REGION="us-east-1"
ACCOUNT_ID="<your-aws-account-id>"       # e.g. 123456789012
VPC_ID="<your-vpc-id>"                   # from EKS → Networking tab

# =============================================================
# STEP 1: Create EKS Cluster with Fargate
# =============================================================
eksctl create cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --fargate

# =============================================================
# STEP 2: Configure kubectl to connect to EKS
# =============================================================
aws eks update-kubeconfig \
  --name $CLUSTER_NAME \
  --region $REGION

# Verify connection
kubectl get nodes

# =============================================================
# STEP 3: Create Fargate Profile for game-2048 namespace
# =============================================================
eksctl create fargateprofile \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --name alb-sample-app \
  --namespace game-2048

# =============================================================
# STEP 4: Deploy 2048 Game (Namespace + Deployment + Service + Ingress)
# =============================================================
kubectl apply -f k8s/2048_full.yaml

# Verify resources
kubectl get all -n game-2048

# Check Ingress (no address yet — ALB controller not installed)
kubectl get ingress -n game-2048

# =============================================================
# STEP 5: Associate IAM OIDC Provider with EKS Cluster
# =============================================================
eksctl utils associate-iam-oidc-provider \
  --cluster $CLUSTER_NAME \
  --approve

# =============================================================
# STEP 6: Create IAM Policy for ALB Controller
# =============================================================
# Download the policy JSON
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.11.0/docs/install/iam_policy.json

# Create the policy in AWS IAM
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

# =============================================================
# STEP 7: Create IAM Service Account (IRSA)
# Creates IAM Role + K8s Service Account and links them
# =============================================================
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve

# =============================================================
# STEP 8: Install AWS ALB Controller via Helm
# =============================================================
# Add EKS Helm repo
helm repo add eks https://aws.github.io/eks-charts

# Update repo
helm repo update eks

# Install ALB Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$REGION \
  --set vpcId=$VPC_ID

# =============================================================
# STEP 9: Verify & Access
# =============================================================
# Check ALB Controller pods are running
kubectl get deployment -n kube-system aws-load-balancer-controller

# Get ALB address (wait 2-3 mins for ALB to provision)
kubectl get ingress -n game-2048

# Open the ADDRESS in your browser to access the 2048 game!

# =============================================================
# CLEANUP — Run after demo to avoid AWS charges
# =============================================================
# eksctl delete cluster --name $CLUSTER_NAME --region $REGION
