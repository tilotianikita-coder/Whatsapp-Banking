import { LightningElement, api } from 'lwc';

/**
 * One-series horizontal bar chart: bars scaled to the largest value, the count (and optional share) at the bar end,
 * a tooltip per bar, and a 'select' event with the bar's key when clickable. Bars are 18px thick with a 4px rounded
 * data end; the selected bar stays full colour and the others dim.
 */
export default class BandhuBarChart extends LightningElement {
    @api items = [];          // [{ key, label, count, note }]
    @api total;               // the share is count / total (blank: no share shown)
    @api color = '#1c5cab';
    @api unit = 'leads';
    @api selected;            // the key of the selected bar
    @api clickable = false;
    @api emptyText = 'Nothing to show yet';
    tip;
    tipX = 0;
    tipY = 0;

    get empty() {
        return !this.items || this.items.length === 0;
    }

    get rows() {
        const items = this.items || [];
        const max = Math.max(1, ...items.map((i) => i.count || 0));
        return items.map((i) => {
            const pct = this.total ? Math.round(((i.count || 0) * 100) / this.total) : null;
            const width = ((i.count || 0) * 100) / max;
            const dim = this.selected && this.selected !== i.key;
            return {
                ...i,
                pctText: pct == null ? '' : ` · ${pct}%`,
                aria: `${i.label}: ${i.count} ${this.unit}`,
                barStyle: `width: ${width}%; background: ${this.color}; opacity: ${dim ? 0.3 : 1};`,
                cls: 'row' + (this.clickable ? ' clickable' : '') + (this.selected === i.key ? ' selected' : '')
            };
        });
    }

    get tipStyle() {
        return `left: ${this.tipX}px; top: ${this.tipY}px;`;
    }

    find(key) {
        return this.rows.find((r) => r.key === key);
    }

    place(evt) {
        const box = this.template.querySelector('.chart').getBoundingClientRect();
        const x = evt.clientX - box.left + 14;
        this.tipX = Math.min(x, box.width - 230);
        this.tipY = evt.clientY - box.top + 12;
    }

    handleEnter(evt) {
        this.tip = this.find(evt.currentTarget.dataset.key);
        this.place(evt);
    }

    handleMove(evt) {
        this.place(evt);
    }

    handleLeave() {
        this.tip = undefined;
    }

    handleClick(evt) {
        if (this.clickable) {
            const key = evt.currentTarget.dataset.key;
            this.dispatchEvent(new CustomEvent('select', { detail: { key: this.selected === key ? null : key } }));
        }
    }

    handleKey(evt) {
        if (evt.key === 'Enter' || evt.key === ' ') {
            evt.preventDefault();
            this.handleClick(evt);
        }
    }
}
