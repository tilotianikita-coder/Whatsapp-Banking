import BANDHAN_LOGO from '@salesforce/resourceUrl/BandhanLogoWhite';
import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getDashboard from '@salesforce/apex/BandhuLeadDashboard.getDashboard';

const BLUE = '#1c5cab';
const PERIODS = [
    { value: 7, label: '7 days' },
    { value: 30, label: '30 days' },
    { value: 90, label: '90 days' },
    { value: 0, label: 'All time' }
];
const CHANNELS = [
    { value: '', label: 'All channels' },
    { value: 'WhatsApp', label: 'WhatsApp' },
    { value: 'Web', label: 'Web' },
    { value: 'Branch', label: 'Branch' }
];
// filter dimension -> the lead row field it matches, and how the filter chip reads
const DIMS = {
    stage: { field: 'stage', label: 'Stopped in', openOnly: true },
    knockoutGate: { field: 'knockoutGate', label: 'Knocked out at' },
    rating: { field: 'rating', label: 'Rating' },
    cibilBand: { field: 'cibilBand', label: 'CIBIL' },
    channel: { field: 'channel', label: 'Channel' },
    card: { field: 'card', label: 'Recommended' },
    region: { field: 'region', label: 'Region' },
    outcome: { field: 'outcome', label: 'Outcome' }
};
// KPI tile -> the filter it applies
const KPI_FILTER = {
    hot: { dim: 'rating', key: 'Hot' },
    open: { dim: 'outcome', key: 'Open' },
    knocked: { dim: 'outcome', key: 'Knocked out' },
    issued: { dim: 'outcome', key: 'Card issued' },
    submitted: { dim: 'outcome', key: 'With underwriting' }
};

function errorMessage(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

function ago(dt) {
    if (!dt) {
        return '—';
    }
    const mins = Math.round((Date.now() - new Date(dt).getTime()) / 60000);
    if (mins < 60) {
        return `${Math.max(1, mins)} min ago`;
    }
    const h = Math.round(mins / 60);
    if (h < 24) {
        return `${h} h ago`;
    }
    return `${Math.round(h / 24)} d ago`;
}

export default class BandhuLeadDashboard extends NavigationMixin(LightningElement) {
    logoUrl = BANDHAN_LOGO;
    blue = BLUE;
    days = 30;
    channel = '';
    data;
    error;
    loading = true;
    filter;            // { dim, key }
    search = '';
    trendTip;
    trendTipStyle = '';

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.data = await getDashboard({ days: this.days, channel: this.channel || null });
            this.error = undefined;
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.loading = false;
        }
    }

    // ------------------------------------------------------------------ filters
    get periods() {
        return PERIODS.map((p) => ({ ...p, cls: 'seg' + (p.value === this.days ? ' on' : '') }));
    }

    get channels() {
        return CHANNELS.map((c) => ({ ...c, cls: 'seg' + (c.value === this.channel ? ' on' : '') }));
    }

    handlePeriod(evt) {
        this.days = Number(evt.currentTarget.dataset.value);
        this.load();
    }

    handleChannel(evt) {
        this.channel = evt.currentTarget.dataset.value;
        this.filter = this.filter && this.filter.dim === 'channel' ? undefined : this.filter;
        this.load();
    }

    handleRefresh() {
        this.load();
    }

    handleSelect(evt) {
        const dim = evt.currentTarget.dataset.dim;
        const key = evt.detail.key;
        this.filter = key == null ? undefined : { dim, key };
        if (key != null) {
            this.scrollToLeads();
        }
    }

    handleKpi(evt) {
        const f = KPI_FILTER[evt.currentTarget.dataset.key];
        this.filter = f && !(this.filter && this.filter.dim === f.dim && this.filter.key === f.key) ? f : undefined;
        if (this.filter) {
            this.scrollToLeads();
        }
    }

    handleClearFilter() {
        this.filter = undefined;
    }

    handleSearch(evt) {
        this.search = (evt.target.value || '').toLowerCase();
    }

    scrollToLeads() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const el = this.template.querySelector('.leads');
            if (el && el.scrollIntoView) {
                el.scrollIntoView({ behavior: 'smooth', block: 'start' });
            }
        }, 50);
    }

    selectedFor(dim) {
        return this.filter && this.filter.dim === dim ? this.filter.key : null;
    }

    get selStage() { return this.selectedFor('stage'); }
    get selKnockout() { return this.selectedFor('knockoutGate'); }
    get selRating() { return this.selectedFor('rating'); }
    get selCibil() { return this.selectedFor('cibilBand'); }
    get selChannel() { return this.selectedFor('channel'); }
    get selCard() { return this.selectedFor('card'); }
    get selRegion() { return this.selectedFor('region'); }

    get filterText() {
        return this.filter ? `${DIMS[this.filter.dim].label}: ${this.filter.key}` : null;
    }

    // ------------------------------------------------------------------ data
    get d() {
        return this.data || {};
    }

    get hasData() {
        return !!this.data;
    }

    get leadCount() {
        return (this.d.leads || []).length;
    }

    get subtitle() {
        const p = PERIODS.find((x) => x.value === this.days);
        const c = CHANNELS.find((x) => x.value === this.channel);
        return `Bandhu card journeys · ${p ? p.label.toLowerCase() : ''} · ${c ? c.label.toLowerCase() : ''}`;
    }

    get kpis() {
        return (this.d.kpis || []).map((k, i) => {
            const f = KPI_FILTER[k.key];
            const on = f && this.filter && this.filter.dim === f.dim && this.filter.key === f.key;
            return { ...k, clickable: !!f, cls: 'kpi' + (i === 0 ? ' kpi-main' : '') + (f ? ' kpi-click' : '') + (on ? ' kpi-on' : '') };
        });
    }

    get funnel() {
        const f = this.d.funnel || [];
        const top = f.length ? Math.max(1, f[0].count) : 1;
        return f.map((s, i) => {
            const pct = Math.round((s.count * 100) / top);
            return {
                ...s,
                pct: `${pct}%`,
                barStyle: `width: ${Math.max((s.count * 100) / top, s.count ? 1.5 : 0)}%;`,
                lost: i > 0 && s.note ? s.note : null,
                step: i + 1
            };
        });
    }

    get biggestLeak() {
        const f = this.d.funnel || [];
        let best = null;
        for (let i = 1; i < f.length; i++) {
            const lost = f[i - 1].count - f[i].count;
            if (lost > 0 && (!best || lost > best.lost)) {
                best = { from: f[i - 1].label, to: f[i].label, lost };
            }
        }
        return best ? `Biggest leak: ${best.from} → ${best.to}, ${best.lost} lost` : null;
    }

    get trend() {
        const t = this.d.trend || [];
        const max = Math.max(1, ...t.map((x) => x.count));
        const step = t.length > 14 ? 7 : 3;
        return t.map((x, i) => ({
            ...x,
            colStyle: `height: ${(x.count * 100) / max}%;`,
            showLabel: (t.length - 1 - i) % step === 0,
            aria: `${x.label}: ${x.count} journeys`
        }));
    }

    get trendMax() {
        return Math.max(1, ...(this.d.trend || []).map((x) => x.count));
    }

    get trendTotal() {
        return (this.d.trend || []).reduce((a, x) => a + x.count, 0);
    }

    get trendDays() {
        return (this.d.trend || []).length;
    }

    handleTrendEnter(evt) {
        const key = evt.currentTarget.dataset.key;
        const t = (this.d.trend || []).find((x) => x.key === key);
        const box = this.template.querySelector('.trend').getBoundingClientRect();
        const col = evt.currentTarget.getBoundingClientRect();
        this.trendTip = t;
        const left = Math.min(Math.max(col.left - box.left - 50, 0), box.width - 130);
        this.trendTipStyle = `left: ${left}px; top: 0px;`;
    }

    handleTrendLeave() {
        this.trendTip = undefined;
    }

    get leadsTotal() {
        return this.leadCount || null;
    }

    get rows() {
        let rows = this.d.leads || [];
        if (this.filter) {
            const dim = DIMS[this.filter.dim];
            rows = rows.filter((r) => r[dim.field] === this.filter.key && (!dim.openOnly || r.outcome === 'Open'));
        }
        if (this.search) {
            rows = rows.filter((r) => (r.name || '').toLowerCase().includes(this.search) || (r.mobile || '').includes(this.search));
        }
        return rows.map((r) => ({
            ...r,
            ratingCls: 'b-pill ' + (r.rating === 'Hot' ? 'b-pill-solid' : r.rating === 'Warm' ? 'b-pill-orange' : 'b-pill-grey'),
            outcomeCls: 'out ' + (r.outcome === 'Knocked out' ? 'out-ko' : r.outcome === 'Card issued' ? 'out-ok' : r.outcome === 'With underwriting' ? 'out-uw' : 'out-open'),
            outcomeIcon: r.outcome === 'Knocked out' ? '✕' : r.outcome === 'Card issued' ? '✓' : r.outcome === 'With underwriting' ? '◷' : '●',
            where: r.outcome === 'Knocked out' ? `${r.knockoutGate}: ${r.knockoutReason || ''}` : r.stoppedAt || 'Not started',
            score: r.combined == null ? '—' : Math.round(r.combined),
            scoreStyle: `width: ${r.combined == null ? 0 : Math.max(0, Math.min(100, r.combined))}%;`,
            cibilText: r.cibil == null ? '—' : Math.round(r.cibil),
            cibilShort: (r.cibilBand || '').split(' (')[0],
            cardText: r.card || '—',
            activity: ago(r.lastActivity),
            nudged: r.lastNudged ? `nudged ${ago(r.lastNudged)}` : null,
            url: `/lightning/r/Lead/${r.id}/view`
        }));
    }

    get rowCount() {
        return this.rows.length;
    }

    get noRows() {
        return this.rows.length === 0;
    }

    handleOpen(evt) {
        evt.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: evt.currentTarget.dataset.id, objectApiName: 'Lead', actionName: 'view' }
        });
    }

    handleListView() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Lead', actionName: 'list' },
            state: { filterName: 'Bandhu_Card_Leads' }
        });
    }
}
