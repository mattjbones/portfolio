# Werf — Static Site Generator Reference

Source: [mattjbones/werf](https://github.com/mattjbones/werf)

## Binary

| Platform | Download URL |
|---|---|
| Linux | `https://github.com/mattjbones/werf/releases/latest/download/werf-linux` |
| macOS | `https://github.com/mattjbones/werf/releases/latest/download/werf-macos` |

Releases are tagged by date (e.g. `2026-02-24`) with a `latest` redirect.

## CLI

```bash
./werf              # Build site (generates dist/)
./werf watch        # Build + watch + local dev server
./werf nowatch      # Single build only (same as bare ./werf)
WERF_LOG=debug ./werf   # Debug output
```

The binary must be run from the site root (the directory containing `_config.yml`).

## _config.yml

```yaml
source: .              # where to read from (relative to cwd)
destination: dist      # output directory

title: Site Title
tagline: subtitle
description: 'A description'
url: https://example.com
baseurl: /

# Optional author block
author:
  name: Name
  email: ""
  username: handle

# Pagination
paginate: 16                  # posts per page
paginate_per_page: 16         # alias (set both)
paginate_path: "/p:num"       # URL pattern for pages 2+

# Files/dirs to exclude from build
exclude:
  - scripts
  - .gitignore
  - dist

# Arbitrary keys become available as site.<key> in templates
image: /public/card_default.jpg
```

## Directory conventions

```
site-root/
  _config.yml
  _layouts/          → Liquid templates
  _includes/         → Liquid partials
  _posts/            → Blog/content posts (YYYY-MM-DD-slug.md)
  _pages/            → Static pages (.md or .html)
  css/               → Copied to dist/, referenced in templates
  public/            → Copied to dist/ (images, favicons, etc.)
  dist/              → Generated output (gitignored)
```

Any directory not prefixed with `_` and not excluded is copied to `dist/`.

## Posts

Filename format: `YYYY-MM-DD-slug.md` (date parsed from filename, not file metadata).

Posts can live in year subdirectories: `_posts/2024/2024-03-15-slug.md`.

Generated URL: `/<year>/<month>/<day>/<slug>/`

### Frontmatter

YAML between `---` delimiters. All fields optional except `layout`.

```yaml
---
layout: post
title: Post Title
tagline: A short subtitle
tags: tag-one tag-two tag-three
image: /public/photo.jpg
unlisted: true          # hide from listings (still accessible by URL)
---
```

If no frontmatter or no `layout` key, werf uses the `default` layout.

## Pages

Files in `_pages/` become top-level routes:
- `_pages/about.md` → `/about/`
- `_pages/index.html` → `/` (homepage)
- `_pages/404.html` → `/404.html`

Both `.md` and `.html` are supported. All are processed through Liquid.

### Dynamic tag pages

A file named `_pages/[tags].html` generates one page per tag automatically. Werf creates a route for each tag found across all posts.

```html
---
layout: default
---
<h2>{{ page.title }}</h2>
```

The `page.title` is set to the tag name. Tag page URLs follow the pattern `/tags/<tag-name>/`.

**Note:** This feature exists in werf but the tag page template has limited access to filtered posts. You may need to filter manually with Liquid:

```liquid
{% for post in site.posts %}
  {% if post.tags contains page.title %}
    ...
  {% endif %}
{% endfor %}
```

## Layouts

Files in `_layouts/` using `.liquid` extension.

Layouts can chain: a layout's frontmatter can specify `layout: default` to wrap in a parent.

```liquid
---
layout: default
---
<div class="post">
  <h1>{{ page.title }}</h1>
  {{ content }}
</div>
```

`{{ content }}` renders the page/post body (or child layout content).

### Layout naming

Layout name in frontmatter maps directly to filename: `layout: photo` → `_layouts/photo.liquid`.

Werf auto-pluralizes folder names for global variables (`_posts` → `site.posts`), but layout filenames are matched exactly as written in frontmatter.

## Includes

Referenced with: `{% include 'name' %}` — no `.liquid` extension, quotes required.

Pass variables: `{% include 'photo-card' post: post %}`

Files live in `_includes/` as `name.liquid`.

## Template variables

### `site` (global)

| Variable | Description |
|---|---|
| `site.posts` | Array of all post objects |
| `site.pages` | Array of all page objects |
| `site.tags` | Tags data |
| `site.title` | From `_config.yml` |
| `site.tagline` | From `_config.yml` |
| `site.url` | From `_config.yml` |
| `site.baseurl` | From `_config.yml` |
| `site.time` | Current build DateTime |
| `site.destination` | Output directory |
| `site.related_posts` | Related posts (may be empty) |
| `site.<key>` | Any custom key from `_config.yml` |

### `page` (per-page/post)

| Variable | Description |
|---|---|
| `page.title` | From frontmatter |
| `page.layout` | Layout name |
| `page.tagline` | From frontmatter |
| `page.tags` | Space-separated tags from frontmatter |
| `page.url` | Generated URL path |
| `page.id` | Filename |
| `page.date` | Post date (from filename for posts) |
| `page.created_year` | Year as integer (e.g. 2024) |
| `page.last_modified_at` | File modification date |
| `page.image` | From frontmatter |
| `page.excerpt` | Auto-extracted excerpt |
| `page.<key>` | Any custom frontmatter key |

### `content`

The rendered body of the current page/post (used in layouts).

## Liquid filters

### Standard (from liquid crate)

All standard Liquid filters work: `where`, `sort`, `reverse`, `truncate`, `strip_html`, `strip_newlines`, `date`, `plus`, `prepend`, `remove`, `size`, etc.

Notable usage:
```liquid
{% assign filtered = site.posts | where: "created_year", 2024 %}
{% assign sorted = site.posts | sort: "created_date" | reverse %}
```

### Custom (werf-specific)

| Filter | Usage | Description |
|---|---|---|
| `date_to_string` | `{{ page.date \| date_to_string }}` | Formats date as "1 Feb 2024" |
| `reading_time_as_s` | `{{ content \| reading_time_as_s }}` | Estimated read time (150 wpm) |

## Liquid tags (custom)

| Tag | Usage | Description |
|---|---|---|
| `post_url` | `{% post_url 2024-03-15-slug %}` | Generates canonical URL for a post |
| `highlight` | `{% highlight js %}...{% endhighlight %}` | Syntax highlighting block |

## Pagination

When `paginate` is set in `_config.yml`, the index page gets paginated.

Available in templates:
- Posts are split into pages of `paginate_per_page` size
- Page 2+ URLs follow `paginate_path` pattern (e.g. `/p2`, `/p3`)

## Static files

Everything in `css/` and `public/` (and any non-`_` prefixed, non-excluded directory) is copied as-is to `dist/`.

Reference in templates using `site.baseurl`:
```liquid
<link rel="stylesheet" href="{{ site.baseurl }}css/main.css">
<img src="{{ site.baseurl }}public/photos/thumbs/image.jpg">
```
