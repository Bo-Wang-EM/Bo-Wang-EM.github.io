---
layout: archive
permalink: /scripts/
title: "Scripts Archive"
author_profile: true
---
## Here, I will share some scripts I've written for electron microscopy image processing.

{% include base_path %}
{% capture written_year %}'None'{% endcapture %}
{% for post in site.scripts reversed %}
  {% capture year %}{{ post.date | date: '%Y' }}{% endcapture %}
  {% if year != written_year %}
    <h2 id="{{ year | slugify }}" class="archive__subtitle">{{ year }}</h2>
    {% capture written_year %}{{ year }}{% endcapture %}
  {% endif %}
  {% include archive-single-script.html %}
{% endfor %}