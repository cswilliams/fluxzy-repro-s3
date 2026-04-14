# Fluxzy Transparent Repro

This repo reproduces a bug where S3 uploads hang when Fluxzy is used in transparent proxy mode.

It is a one-container Linux repro for the transparent HTTPS interception path:

- Ubuntu Noble
- Fluxzy `ReverseSecure`
- local `iptables` `OUTPUT` redirect from `443` to Fluxzy
- AWS CLI upload inside the same container

## Build

```bash
docker build -t fluxzy-transparent-repro .
```

## Run With The Generated ~80 KB Test File

First, export temporary AWS credentials in your host shell. `AWS_DEFAULT_REGION` should match the region of the bucket in `S3_URI`.

```bash
docker run --rm -it \
  --cap-add=NET_ADMIN \
  --env AWS_ACCESS_KEY_ID \
  --env AWS_SECRET_ACCESS_KEY \
  --env AWS_SESSION_TOKEN \
  --env AWS_DEFAULT_REGION=your-region \
  --env S3_URI=s3://your-bucket/fluxzy.txt \
  --volume "$PWD/fluxzy-dump:/dump" \
  fluxzy-transparent-repro
```

The container will:

1. create a Fluxzy root CA
2. start Fluxzy on `127.0.0.1:18443`
3. redirect outbound `tcp/443` to Fluxzy
4. generate an approximately 80 KB local payload file at `/tmp/payload.txt`
5. capture Fluxzy dump files to `/dump`
6. run `aws --debug s3 cp`
