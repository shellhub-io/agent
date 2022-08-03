package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"strings"

	"github.com/containers/image/v5/copy"
	"github.com/containers/image/v5/signature"
	"github.com/containers/image/v5/transports/alltransports"
	"github.com/mholt/archiver/v3"
	"github.com/sirupsen/logrus"
)

type Manifest struct {
	MediaType     string          `json:"mediaType"`
	SchemaVersion int             `json:"schemaVersion"`
	Layers        []ManifestLayer `json:"layers"`
}

type ManifestLayer struct {
	Digest string `json:"digest"`
}

func main() {
	dir, err := downloadImage("v0.9.4")
	if err != nil {
		logrus.Fatal(err)
	}

	if err := extractImage(dir, "/tmp/shellhub_agent_rootfs"); err != nil {
		logrus.Fatal(err)
	}

	os.RemoveAll(dir)
}

// downloadImage download ShellHub Agent docker image version from registry
// and returns a path to a directory containing the manifest file and it's
// compressed image layers
func downloadImage(version string) (string, error) {
	policyContext, err := signature.NewPolicyContext(&signature.Policy{
		Default: []signature.PolicyRequirement{
			signature.NewPRInsecureAcceptAnything(),
		},
	})
	if err != nil {
		return "", err
	}
	defer policyContext.Destroy()

	image := fmt.Sprintf("docker://registry-1.docker.io/shellhubio/agent:%s", version)

	src, err := alltransports.ParseImageName(image)
	if err != nil {
		return "", err
	}

	dir, err := os.MkdirTemp("", "shellhub_image")
	if err != nil {
		return "", err
	}

	dst, err := alltransports.ParseImageName(fmt.Sprintf("dir:%s", dir))
	if err != nil {
		os.RemoveAll(dir)
		return "", err
	}

	if _, err = copy.Image(context.Background(), policyContext, dst, src, nil); err != nil {
		os.RemoveAll(dir)
		return "", err
	}

	return dir, nil
}

// extractImage extracts compressed image layers from a directory containing
// an manifest.json file to a target directory
func extractImage(from, target string) error {
	f, err := os.Open(fmt.Sprintf("%s/manifest.json", from))
	if err != nil {
		return err
	}
	defer f.Close()

	jsonData, err := ioutil.ReadAll(f)
	if err != nil {
		return err
	}

	var manifest Manifest
	if err := json.Unmarshal(jsonData, &manifest); err != nil {
		return err
	}

	for _, layer := range manifest.Layers {
		// determines the filename from digest without sha256: prefix
		filename := strings.TrimPrefix(layer.Digest, "sha256:")

		targz := archiver.NewTarGz()
		if err := targz.Unarchive(fmt.Sprintf("%s/%s", from, filename), target); err != nil {
			return err
		}
	}

	return nil
}
