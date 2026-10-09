# 서비스 서버(sky-platform) 이미지 태그. 7자리 git SHA.
# 이 파일만 바꾼 PR이 main에 머지되면 .github/workflows/platform-image.yml이 태스크 정의와 ECS 서비스만 적용한다.
# 태그에 해당하는 이미지가 ECR sky-platform 레포에 먼저 있어야 한다.
platform_image_tag = "210ced5"
