# Claude Code Instructions

## Project docs

- [README.md](./README.md) — project overview, site structure, frontmatter schema, scripts, deployment
- [WERF.md](./WERF.md) — werf SSG reference (binary, config, templates, variables, filters)

## Commit style

Use [Conventional Commits](https://www.conventionalcommits.org/). Each commit message must have:

1. A **type** prefix: `feat`, `fix`, `chore`, `ci`, `docs`, `refactor`, `style`
2. A short imperative **subject** line
3. A **body** with two labelled lines:
   - `Problem:` what was wrong or missing
   - `Solution:` what was done to address it

### Format

```
<type>: <short subject>

Problem: <what was wrong or missing>
Solution: <what was done>
```

### Examples

```
feat: add film metadata fields from XMP data

Problem: film frontmatter used a single freeform string with no structured breakdown.
Solution: replaced with film_name, film_format, film_speed, film_type sourced from XMP hierarchical subjects.
```

```
fix: guard contains filter against nil tags

Problem: werf errors when tags is nil and contains is called on it.
Solution: added `and post.tags` guard before all contains checks.
```
