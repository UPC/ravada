---
name: 📖 Documentation Change
about: Suggest an addition or modification to the Ravada documentation
labels: ["documentation"]
---
body:
  - type: dropdown
    attributes:
      label: Change Type
      description: What type of change are you proposing?
      options:
        - Addition
        - Correction
        - Removal
        - Cleanup (formatting, typos, etc.)
    validations:
      required: true
  - type: dropdown
    attributes:
      label: Area
      description: Which section of the documentation is this change to?
      options:
        - Features
	      - Administrator
	      - Guest VM
	      - Development
        - Other
    validations:
      required: true
  - type: textarea
    attributes:
      label: Proposed Changes
      description: Describe the proposed changes and why they are necessary.
    validations:
      required: true
