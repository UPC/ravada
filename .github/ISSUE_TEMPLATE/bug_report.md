---
name: ⚠️  Bug Report
about: Report a reproducible bug in the current release of Ravda
labels: ["bug"]
---
body:
  - type: markdown
    attributes:
  - type: input
    attributes:
      label: Ravada version
      description: What version of Ravada are you currently running?
      placeholder: 
    validations:
      required: true
  - type: dropdown
    attributes:
      label: Client/Server
      description: What browser do you have?
      options:
        - "Server"
        - "Client"
    validations:
      required: true
  - type: dropdown 
    attributes: 
      label: Operating System 
      description: What operating system are you using?
      options: 
        - "Ubuntu" 
        - "Windows" 
      visibleWhen: 
        - field: Client/Server value: "Client" 
    validations: 
      required: true
  - type: dropdown 
    attributes: 
      label: Operating System 
      description: What operating system are you using? 
      options: 
        - "Ubuntu Server" 
        - "Windows Server" 
        - "Ubuntu" 
        - "Windows" 
        visibleWhen: 
          - field: Client/Server value: "Server" 
      validations: 
        required: true
  - type: dropdown
    attributes:
      label: Browser
      description: What browser do you have?
      options:
        - "Firefox"
        - "Chrome"
        - "Microsoft Edge"
        - "Opera"
        - "Others"
    validations:
      required: true
  - type: textarea
    attributes:
      label: Steps to Reproduce
      description: >
        A clear and concise description of what you expected to happen.
      placeholder: |   
    validations:
      required: true
  - type: textarea
    attributes:
      label: Expected Behavior
      description: What did you expect to happen?
      placeholder: 
    validations:
      required: true
  - type: textarea
    attributes:
      label: Observed Behavior
      description: What happened instead?
      placeholder: A TypeError exception was raised
    validations:
      required: true
