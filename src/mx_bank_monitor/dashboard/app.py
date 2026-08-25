from __future__ import annotations

import streamlit as st


def main() -> None:
    st.set_page_config(page_title="Mexico Banking Monitor", page_icon="🏦", layout="wide")
    st.title("Mexico Banking Monitor")
    st.caption("Auditable monthly banking intelligence from CNBV regulatory disclosures")
    st.info(
        "The data pipeline is ready for source mapping. "
        "The dashboard will populate after the first validated CNBV ingestion."
    )

    left, middle, right = st.columns(3)
    left.metric("Latest period", "Pending first load")
    middle.metric("Institutions", "—")
    right.metric("Pipeline status", "Bootstrap")

    st.subheader("Planned analytical views")
    st.markdown(
        """
        - System overview and institution ranking
        - Growth and profitability
        - Asset quality, coverage, cost of risk, and capital
        - Funding and loans-to-deposits
        - Traditional banks vs digital-first banks
        - Separate digital SOFIPO panel
        """
    )


if __name__ == "__main__":
    main()
