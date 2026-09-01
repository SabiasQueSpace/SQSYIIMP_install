#!/usr/bin/env bash
#########################################################
# SQSYIIMP version helper
# SabiasQue.Space
#########################################################

if [ -z "${TAG:-}" ]; then
    TAG=v1.0.2
fi

echo "VERSION=${TAG}" | sudo -E tee /etc/yiimpoolversion.conf >/dev/null 2>&1
