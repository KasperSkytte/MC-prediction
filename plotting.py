import matplotlib.pyplot as plt
import numpy as np
import seaborn as sns
from sklearn.manifold import TSNE
from preprocessing import smooth

import json
with open('config.json', 'r') as config_file:
    _fig_dir = json.load(config_file)['figures_dir']

def plot_results(func, prediction, dates, asv):
    """Plot the true vs. the predicted values for the specified ASV."""
    x_labels_spacing = np.arange(0, func.shape[0], step=1+(func.shape[0] // 10))
    x_labels = [dates[i] for i in x_labels_spacing]

    plt.plot(func[asv], label='Truth')
    plt.plot(prediction[asv], label='Prediction')
    plt.title(asv)
    plt.ylabel('Abundance')
    plt.ylim(ymin=0)
    plt.legend()
    plt.xticks(x_labels_spacing, labels=x_labels, rotation=45, ha='right')
    plt.show()

def plot_four_results(func, prediction, dates, asvs, higlight_dates=None, save_filename=None):
    """Create four subplots of the true vs. the predicted values of the four specified ASVs."""
    x_labels_spacing = np.arange(0, func.shape[0], step=1+(func.shape[0] // 20))
    x_labels = [dates[i] for i in x_labels_spacing]

    if higlight_dates:
        vertical_lines = np.where(np.isin(dates, higlight_dates))

    fig, axes = plt.subplots(2, 2, sharex=True)
    fig.set_size_inches(14, 8)
    fig.suptitle('Truth vs. Prediction')
    axes_flat = [x for x in axes.flat]

    for i in range(4):
        axis = axes_flat[i]
        axis.set(ylabel='Abundance')
        axis.set_xticks(x_labels_spacing)
        axis.set_xticklabels(x_labels, rotation=45, ha='right')

        if i < len(asvs):
            asv = asvs[i]        
            axis.set_title(asv)
            axis.plot(func[asv], label='Truth')
            axis.plot(prediction[asv], label='Prediction')
            axis.set_ylim(ymin=0)
            axis.legend()
            if higlight_dates:
                axis.vlines(vertical_lines, -100, 100, colors='r')

    if save_filename:
        plt.savefig(_fig_dir + save_filename, dpi=100, bbox_inches='tight')
    else:
        plt.show()


def plot_abundance_within_clusters(abundances, clusters, func_tax, asvs_per_plot=10):
    plt.figure(figsize=(10,6))
    unique_clusters= np.unique(clusters)
    for i in unique_clusters:
        x = abundances[clusters == i]
        labels = func_tax[clusters == i]
        cluster_size = len(x)
        plt.title(f'Cluster {i+1} ({cluster_size} ASVs in total)')

        for j in range(x.shape[0]):
            if j % ((x.shape[0] // asvs_per_plot)+1) == 0:
                plt.plot(x[j], label=labels[j,0])
        plt.legend()
        plt.savefig(_fig_dir + 'cluster' + str(i+1) + '.png', bbox_inches='tight')
        plt.close()


def train_tsne(data):
    tsne = TSNE()
    return tsne.fit_transform(data)

def plot_tsne(data_embedded, clusters, n_clusters, cluster_type):
    plt.figure(figsize=(10,6))
    palette = sns.color_palette('bright', np.unique(clusters).size)
    clusters1 = clusters + 1
    sns.scatterplot(x=data_embedded[:,0], y=data_embedded[:,1], hue=clusters1, legend='full', palette=palette)
    plt.title(f"t-SNE for {cluster_type} clusters")
    plt.savefig(_fig_dir + 'tsne_for_' + cluster_type.lower() + '.png', bbox_inches='tight')
    plt.close()


def create_boxplot(data, label, cluster_type):
    plt.figure(figsize=(8,5))
    plt.boxplot(data, whis=4, medianprops=dict(color='black'))
    plt.ylim(bottom=-0.01, top=1.01)
    plt.ylabel(label)
    plt.title(f"{label} for each {cluster_type} cluster")
    plt.savefig(_fig_dir + 'boxplot_' + cluster_type.lower() + '.png', bbox_inches='tight')
    plt.close()


if __name__ == "__main__":
    from preprocessing import preprocess_data, smooth, normalize
    from correlation import calc_cluster_correlations, print_corr_results
    from idec.IDEC import IDEC

    import json
    with open('config.json', 'r') as config_file:
        config = json.load(config_file)

    x, func_tax, func_clusters, _ = preprocess_data(config['abund_filename'], config)
    x = smooth(x)

    n_clusters = 5
    plt.rcParams['figure.figsize'] = (12,8)

    idec = IDEC(dims=[x.shape[-1], 500, 500, 2000, 10], n_clusters=n_clusters)
    idec.load_weights(config['results_dir'] + 'idec/IDEC_best.h5')
    idec_clusters = idec.predict_clusters(x)

    print('\nfunction clustering:')
    cluster_sizes, r_values, p_values = calc_cluster_correlations(x, func_clusters, n_clusters)
    print_corr_results(cluster_sizes, r_values, p_values)
    create_boxplot(r_values, 'abs(r-values)', 'func')
    create_boxplot(p_values, 'p-values', 'func')
    plot_tsne(x, func_clusters, n_clusters, 'func')
    plot_abundance_within_clusters(x, func_clusters, func_tax)

    print('\nIDEC clustering:')
    cluster_sizes, r_values, p_values = calc_cluster_correlations(x, idec_clusters, n_clusters)
    print_corr_results(cluster_sizes, r_values, p_values)
    create_boxplot(r_values, 'abs(r-values)', 'idec')
    create_boxplot(p_values, 'p-values', 'idec')
    plot_tsne(x, idec_clusters, n_clusters, 'idec')
    plot_abundance_within_clusters(x, idec_clusters, func_tax)
