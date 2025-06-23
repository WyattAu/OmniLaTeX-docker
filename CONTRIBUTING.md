# Contribution Guide

## Setup

1. Fork this repo

## Guidelines

### Contribution Related Guidence

- Branch naming: `staging/feat/description`, `staging/fix/description`.
- Since `staging` branch is periodically reviewed and merged into `main` by admin, you can directly commit on `staging` without waiting for pull requests.

### Formatting and Structure

#### Naming Conventions

| Type                 | Convention                                                    | Examples                                        |
| -------------------- | ------------------------------------------------------------- | ----------------------------------------------- |
| **Folders**          | lowercase-kebab                                               | `api-reference/`, `data-models/`                |
| **Markdown Files**   | lowercase-kebab                                               | `getting-started.md`, `api-v3.md`               |
| **React Components** | camelCase                                                     | `themeToggle.tsx`, `codeBlock.js`               |
| **Utility Files**    | camelCase                                                     | `formatDate.js`, `stringUtils.ts`               |
| **Assets/Images**    | lowercase_snake for tags, lowercase-kebab for each identifier | `Logo_ib-logo.webp`, `diagram_carnot-cycle.svg` |
| **Config Files**     | camelCase                                                     | `sidebarItems.js`, `footerLinks.js`             |
| **Variables**        | camelCase                                                     | `currentUser`, `pageMetadata`                   |
| **Constants**        | UPPER_SNAKE_CASE                                              | `API_ENDPOINT`, `MAX_ITEMS`                     |
