// WIP: Part of https://github.com/awslabs/mountpoint-s3-csi-driver/issues/279.
//
// `aws-s3-csi-mounter` is the entrypoint binary running on Mountpoint Pods.
// It is responsible for receiving mount options from the CSI Driver Node Pod,
// and spawning a Mountpoint instance in turn.
// It will then wait until Mountpoint process terminates (which normally happens as a result of `unmount`).
package main

import (
	"context"
	"flag"
	"os"
	"path/filepath"
	"time"

	"k8s.io/klog/v2"

	"github.com/awslabs/mountpoint-s3-csi-driver/cmd/aws-s3-csi-mounter/csimounter"
	"github.com/awslabs/mountpoint-s3-csi-driver/pkg/mountpoint/mountoptions"
	"github.com/awslabs/mountpoint-s3-csi-driver/pkg/podmounter/mppod"
)

var mountSockRecvTimeout = flag.Duration("mount-sock-recv-timeout", 2*time.Minute, "Timeout for receiving mount options from passed Unix socket.")
var mountpointBinDir = flag.String("mountpoint-bin-dir", os.Getenv("MOUNTPOINT_BIN_DIR"), "Directory of mount-s3 binary.")

var mountSockPath = mppod.PathInsideMountpointPod(mppod.KnownPathMountSock)
var mountExitPath = mppod.PathInsideMountpointPod(mppod.KnownPathMountExit)
var mountErrorPath = mppod.PathInsideMountpointPod(mppod.KnownPathMountError)

const mountpointBin = "mount-s3"

func main() {
	klog.InitFlags(nil)
	flag.Parse()

	mountpointBinFullPath := filepath.Join(*mountpointBinDir, mountpointBin)
	mountOptions, err := recvMountOptions()
	if err != nil {
		if csimounter.ShouldExitWithSuccessCode(mountExitPath) {
			klog.Info("Failed to receive mount options and detected `mount.exit` file, exiting with zero code")
			os.Exit(csimounter.SuccessExitCode)
			return
		}

		klog.Fatalf("Failed to receive mount options from %s: %v\n", mountSockPath, err)
	}

	exitCode, err := csimounter.Run(csimounter.Options{
		MountpointPath: mountpointBinFullPath,
		MountExitPath:  mountExitPath,
		MountErrPath:   mountErrorPath,
		MountOptions:   mountOptions,
	})
	if err != nil {
		klog.Fatalf("Failed to run Mountpoint: %v\n", err)
	}
	klog.Infof("Mountpoint exited with %d exit code\n", exitCode)
	os.Exit(exitCode)
}

func recvMountOptions() (mountoptions.Options, error) {
	ctx, cancel := context.WithTimeout(context.Background(), *mountSockRecvTimeout)
	defer cancel()
	klog.Infof("Trying to receive mount options from %s", mountSockPath)
	options, err := mountoptions.Recv(ctx, mountSockPath)
	if err != nil {
		return mountoptions.Options{}, err
	}
	klog.Infof("Mount options has been received from %s", mountSockPath)
	return options, nil
}
