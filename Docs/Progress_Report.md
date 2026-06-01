# Session Progress Report

**Date:** June 1, 2026
**Project:** Football Coach Valuation Model
**Author:** Andrew Salisbury

---

## Context

This session's work sits within Milestone 5 of the project (Coach Attribution and Rankings, target July 25), which requires knowing which coach managed each team during each season. Before residuals can be attributed to coaches, a data source for coach-team-season assignments must be identified and integrated. That was the focus of this session.

---

## What Was Accomplished

### Identifying a Data Source for Coach History

The first task was finding a reliable source for coach data. After exploring the Transfermarkt website — the same source used for all other project data — it was found that the team season pages already used for squad data also contain coach information. Specifically, each page lists every manager who took charge during that season, along with the exact dates their tenure began and ended.

This was a meaningful find: it means coach data can be collected from pages the project already visits, without introducing a new data source or scraping additional pages.

### Building the Coach Data Layer

A scraper was built and integrated into the project's existing data infrastructure, following the same caching pattern used for squad and match data. The scraper collects the coach's name, a unique identifier, and their start and end dates for each team-season.

The implementation was validated against two test cases:

- **Manchester City 2024** returned one coach (Pep Guardiola) with correct tenure dates, confirming the basic case works.
- **Barcelona 2019** returned two coaches — Ernesto Valverde and Quique Setién — with a handover date of January 13, 2020, matching the well-documented mid-season dismissal. This confirmed that mid-season changes are captured correctly.

### Designing the Mid-Season Attribution Approach

A key methodological decision was made regarding how to handle seasons with a mid-season manager change. The naive approach — assigning the full season's result to one coach — would introduce noise and unfairness into the rankings. Instead, the plan is to attribute only the matches each coach actually managed.

Each coach's performance will be measured as their actual points in those matches versus the points the model would have expected given the number of games they managed. This is expressed as a points-per-game rate, which also makes it consistent with how the project handles the Bundesliga (which plays 34 games per season rather than 38).

To support this approach, match dates were added to the match data so that each match can be assigned to the correct coach based on tenure dates.

---

## Problems Encountered

Two bugs in the existing codebase were identified and fixed during this session:

1. **Re-scraping duplication:** When the scraper was told to re-fetch data it had already collected, it was appending new results on top of old ones rather than replacing them. This has been corrected.

2. **Schema mismatch:** Adding the match date field to match data created a compatibility issue with the existing cached data, which was collected before dates were tracked. This was resolved so that old and new data can coexist cleanly.

---

## What Remains Before Coach Rankings Can Be Produced

The infrastructure built this session is ready but not yet populated. Three steps remain before coach data can feed into the residual analysis:

1. **Run the coach scraper across all team-seasons** — the scraper has been tested on individual cases but needs to be run across the full dataset (~1,000 team-seasons across five leagues and ten seasons)
2. **Re-collect match dates** — existing match data needs to be refreshed to include the new date field
3. **Implement the attribution logic** — the code that assigns each match to its coach by date range and computes per-coach points totals

These steps are planned for a future session once Milestone 3 (Model Comparison, target June 6) is complete.
