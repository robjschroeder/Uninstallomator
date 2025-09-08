# How to assemble Uninstallomator.sh

To reduce merge conflicts and make contributions easier, the main script is split into multiple fragments. This modular approach allows for easier updates to logic and labels.

## What changes when I _use_ the script?

Nothing changes for end users. You still use the assembled `Uninstallomator.sh` script from the root of the repository, or install it via the provided installer package. The changes only affect contributors who want to build or modify labels or script logic.

## How do I build my own labels?

The script is broken into fragments for easier management. Individual fragments are not functional on their own. To assemble and run Uninstallomator with your custom labels, use the `utils/assemble.sh` tool.

**Steps to create labels:**
1. Clone to repo to your computer
2. Run the buildLabel.sh script while passing an installed App's path: 
    `/path/to/Uninstallomator/utils/buildLabel.sh /Applications/Microsoft\ Edge.app`
3. The label will be written to: /path/to/Uninstallomator/fragments/labels/labelName.sh
4. Assemble your script using the following command: 
    `/path/to/Uninstallomator/utils/assemble.sh --script`
5. You can now run ./Uninstallomator labelName to test. 

## How do I contribute new or modified labels?

If you’re familiar with git and GitHub:
- Fork the Uninstallomator repo and clone it locally.
- Create a new branch for your changes.
- Copy your new or modified label file to `fragments/labels`.
- Test your changes.
- Create a pull request (PR) against the `main` branch.

Please submit one label per PR for clarity. If you have multiple changes, use separate branches and PRs.

## Fragments

Fragments are assembled in this order (all in the `fragments` directory):
- header.sh
- version.sh
- functions.sh
- arguments.sh
- labels/*.sh
- main.sh

Fragments use the `.sh` extension for editor compatibility, even though they are not standalone scripts.

## assemble.sh Usage

Basic usage:
```
assemble.sh
```
Assembles the script and writes it to `build/Uninstallomator.sh`, then executes it.

To run with a specific label:
```
assemble.sh <label>
assemble.sh <label> <VAR=value>...
```

To build for release:
```
assemble.sh --script
assemble.sh --pkg
assemble.sh --notarize
```
See the top of `assemble.sh` for variables to customize for your developer certificates.