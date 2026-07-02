name: Build Ubuntu 26.04 Stable RootFS

on:
  workflow_dispatch:
    inputs:
      desktop_env:
        description: 'Desktop environment: gnome, kde, or xfce'
        required: true
        default: 'gnome'
        type: choice
        options:
          - gnome
          - kde
          - xfce

permissions:
  contents: read
  actions: write

jobs:
  build-rootfs:
    name: Build Ubuntu 26.04 ${{ github.event.inputs.desktop_env }} with stable kernel 7.0.12
    runs-on: ubuntu-24.04-arm
    timeout-minutes: 360
    steps:
      - uses: actions/checkout@v4
        with:
          ref: sheng

      - name: Install build tools
        run: |
          sudo apt update
          sudo apt install -y debootstrap libarchive-tools p7zip-full curl wget android-sdk-libsparse-utils

      - name: Download stable kernel 7.0.12 packages
        run: |
          set -eux
          base="https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/releases/download"
          curl -L --retry 3 -o linux-xiaomi-sheng.deb "$base/kernel-7.0/linux-xiaomi-sheng.deb"
          curl -L --retry 3 -o firmware-xiaomi-sheng.deb "$base/kernel-7.0/firmware-xiaomi-sheng.deb"
          curl -L --retry 3 -o alsa-xiaomi-sheng.deb "$base/kernel-7.0/alsa-xiaomi-sheng.deb"
          curl -L --retry 3 -o sheng-devauth.deb "$base/sheng_devauth/sheng-devauth.deb"
          curl -L --retry 3 -o fastrpc_1.0.2-1_arm64.deb "$base/sensor/fastrpc_1.0.2-1_arm64.deb"
          curl -L --retry 3 -o iio-sensor-proxy_99993.8-6_arm64.deb "$base/sensor/iio-sensor-proxy_99993.8-6_arm64.deb"
          curl -L --retry 3 -o libssc_0.4.2-1_arm64.deb "$base/sensor/libssc_0.4.2-1_arm64.deb"
          curl -L --retry 3 -o sheng-sensors_20240917-1_arm64.deb "$base/sensor/sheng-sensors_20240917-1_arm64.deb"
          dpkg-deb -f linux-xiaomi-sheng.deb Package Version Architecture
          test "$(dpkg-deb -f linux-xiaomi-sheng.deb Version)" = "7.0.12-sm8550-ge42d4dd4c83a"
          ls -lh *.deb

      - name: Build RootFS
        run: |
          set -eux
          chmod +x build-ubuntu26-rootfs.sh
          sudo ./build-ubuntu26-rootfs.sh 7.0 "${{ github.event.inputs.desktop_env }}"
          ls -lh ubuntu26_${{ github.event.inputs.desktop_env }}_*.7z

      - name: Upload rootfs artifact
        uses: actions/upload-artifact@v4
        with:
          name: ubuntu26-${{ github.event.inputs.desktop_env }}-stable-kernel-7.0.12
          path: ubuntu26_${{ github.event.inputs.desktop_env }}_*.7z
          retention-days: 7
          if-no-files-found: error
