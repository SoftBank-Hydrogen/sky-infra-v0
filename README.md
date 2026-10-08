# sky-infra

Sky가 사용하는 **공통 인프라**의 Terraform 저장소입니다. 앱별 서비스·이미지·DB는
[`sky-platform`](https://github.com/SoftBank-Hydrogen/sky-platform)이 배포 시 관리합니다.
두 저장소에서 같은 리소스를 동시에 관리하지 않습니다.

## 팀원이 지금 할 수 있는 작업

저장소를 clone해 Terraform 코드를 수정하고 PR을 열 수 있습니다. PR의 GitHub Actions는
`fmt`와 `validate`를 실행합니다. 로컬에서도 AWS 계정 없이 같은 정적 검사를 할 수 있습니다.

```sh
git clone https://github.com/SoftBank-Hydrogen/sky-infra.git
cd sky-infra
terraform fmt -check -recursive
terraform -chdir=bootstrap init -backend=false -input=false
terraform -chdir=bootstrap validate
terraform -chdir=envs/dev init -backend=false -input=false
terraform -chdir=envs/dev validate
```

Terraform 1.10 이상이 필요하며, CI는 1.15.8을 사용합니다. 새 작업은 별도 브랜치에서
진행하고 PR로 검토합니다. `terraform apply`는 팀의 공용 state와 실행 역할을 준비한 뒤
담당자가 한 경로에서 실행합니다.

## 현재 구성과 준비 상태

| 경로 | 용도 | 현재 상태 |
| --- | --- | --- |
| `bootstrap/` | 공용 Terraform state용 S3 버킷 | 코드만 있음, 미적용 |
| `envs/dev/` | 개발 환경의 GitHub OIDC 역할·SSM 출력값 | 코드만 있음, 미적용 |
| `modules/aws/` | OIDC 역할과 공개 출력값 모듈 | 구현됨 |
| `.github/workflows/terraform.yml` | 정적 검사, 역할 설정 후 plan·apply | 정적 검사만 사용 가능 |

실제 Sky 배포는 `ap-northeast-2`에서 동작합니다. Terraform 예시의 기본 리전도 여기에
맞췄습니다. 현재 플랫폼은 SSM 출력값을 자동으로 읽거나 Terraform의 배포 역할을 위임받지
않으며, 별도로 설정된 AWS 자격 증명과 `SKY_AWS_REGION`·`SKY_AWS_ACCOUNT_ID`를 씁니다.
GCP와 온프레미스 공통 기반은 이 저장소에서 아직 구현되지 않았습니다.

## 두 AWS 계정의 역할

| 계정 | 용도 | 실행 경로 |
| --- | --- | --- |
| 개인 계정 | 개인 개발·실배포 검증 | 로컬 AWS 자격 증명과 `SKY_AWS_ACCOUNT_ID` |
| 팀 공유 계정 | 팀 공동 배포와 인프라 상태 | 이 저장소의 GitHub Actions OIDC 역할·S3 state |

GitHub Actions의 plan/apply는 **팀 공유 계정만** 대상으로 설정합니다. 저장소 변수
`AWS_ACCOUNT_ID`와 역할을 맡은 뒤 STS가 반환한 계정 ID가 다르면 Terraform 실행 전에
중단됩니다. 개인 계정의 역할 ARN·state 버킷은 이 저장소의 GitHub 변수에 넣지 않습니다.
개인 검증 시에는 Sky를 실행하는 셸에서 자기 계정 자격 증명과
`SKY_AWS_ACCOUNT_ID=<개인 계정 ID>`를 사용합니다. 팀 계정에서 Sky를 실행할 때는
팀 계정 자격 증명과 해당 계정 ID로 설정합니다. 두 계정은 state·ECR·ECS 리소스를
공유하지 않으며, 현재 Sky는 한 프로세스에서 AWS 대상 계정 하나를 사용합니다.

## 공동 AWS 적용을 시작하기 전에

1. 담당자 한 명이 대상 AWS 계정과 리전을 확인하고 `bootstrap/`을 **한 번만** 적용합니다.
   이때 생긴 로컬 `bootstrap/terraform.tfstate`는 Git에 올리지 않고 팀이 정한 비공개
   장소에 보관합니다.
2. S3 버킷을 `envs/dev/backend.hcl`에 설정합니다. 예시는
   `envs/dev/backend.hcl.example`에 있습니다. `terraform.tfvars.example`도 복사해
   계정에 맞게 채웁니다. 두 실제 설정 파일은 `.gitignore` 대상입니다.
3. GitHub OIDC 공급자의 기존 존재 여부와 plan·apply 역할의 권한을 검토한 뒤
   `envs/dev`를 적용합니다. 현재 예시의 apply 정책 목록은 비어 있으므로 그대로는
   CI에서 기반 리소스를 변경할 권한이 없습니다.
4. GitHub 저장소 변수 `AWS_ACCOUNT_ID`, `TF_STATE_BUCKET`, `AWS_REGION`, `AWS_PLAN_ROLE_ARN`,
   `AWS_APPLY_ROLE_ARN`, `INFRA_APPLY_POLICY_ARNS`와 `dev` environment 승인을 설정합니다.
   그 뒤 PR plan과 승인된 apply를 활성화합니다.

state 버킷과 역할이 아직 없는 동안에는 각자 로컬 state로 `envs/dev`를 적용하지 마세요.
팀원에게 관리자 액세스 키를 공유할 필요도 없습니다.
