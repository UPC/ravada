name:⚠️  Bug Report
description: Report a reproducible bug in the current release of NetBox
labels: ["bug"]
body:
  - type: markdown
    attributes:
  - type: input
    attributes:
      label: NetBox version
      description: What version of NetBox are you currently running?
      placeholder: v3.6.4
    validations:
      required: true
  - type: dropdown
    attributes:
      label: Python version
      description: What version of Python are you currently running?
      options:
        - "3.8"
        - "3.9"
        - "3.10"
        - "3.11"
    validations:
      required: true
  - type: textarea
    attributes:
      label: Steps to Reproduce
      description: >
        Describe in detail the exact steps that someone else can take to
        reproduce this bug using the current stable release of NetBox. Begin with the
        creation of any necessary database objects and call out every operation being
        performed explicitly. If reporting a bug in the REST API, be sure to reconstruct
        the raw HTTP request(s) being made: Don't rely on a client library such as
        pynetbox. Additionally, **do not rely on the demo instance** for reproducing
        suspected bugs, as its data is prone to modification or deletion at any time.
      placeholder: |   
	1. Go to '...'
        2. Click on '...'
        3. Scroll down to
	4. See error
    validations:
      required: true
  - type: textarea
    attributes:
      label: Expected Behavior
      description: What did you expect to happen?
      placeholder: A new widget should have been created with the specified attributes
    validations:
      required: true
  - type: textarea
    attributes:
      label: Observed Behavior
      description: What happened instead?
      placeholder: A TypeError exception was raised
    validations:
      required: true
