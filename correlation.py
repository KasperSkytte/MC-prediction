from scipy.stats import pearsonr
import numpy as np

def calc_cluster_correlations(abundances, clusters, n_clusters):
    """Calculates the pairwise Pearson correlation between all taxa in each cluster."""
    r_values = [[] for _ in range(n_clusters)]
    p_values = [[] for _ in range(n_clusters)]
    cluster_sizes = []

    # To avoid a very weird bug causing NaN in correlation results when also creating boxplots.
    pearsonr(abundances[0], abundances[0])

    for c in range(n_clusters):
        cluster_data = abundances[clusters == c]
        cluster_size = len(cluster_data)
        cluster_sizes.append(cluster_size)
        if cluster_size < 2:
            r_values[c].append(1.0)
            p_values[c].append(0.0)
            continue
        
        for i in range(cluster_size):
            for j in range(i+1, cluster_size):
                r, p = pearsonr(cluster_data[i], cluster_data[j])
                r_values[c].append(r)
                p_values[c].append(p)

    abs_r_values = [np.abs(result) for result in r_values]
    return cluster_sizes, abs_r_values, p_values


def calc_correlation_aggregates(cluster_sizes, r_values, p_values):
    """Calculates the average of and standard deviation of the correlation in each cluster."""
    means = [np.mean(r) for r in r_values]
    stds = [np.std(r) for r in r_values]
    p_means = [np.mean(p) for p in p_values]
    weighted_avg = np.average(means, weights=cluster_sizes)
    return means, stds, p_means, weighted_avg


def print_list_rounded(title, num_list):
    print(title, '[', end='')
    for i in range(len(num_list)):
        print(f'{num_list[i]:.3f}', end='')
        if i < (len(num_list) - 1):
            print(', ', end='')
    print(']')


def print_corr_results(cluster_sizes, r_values, p_values):
    means, stds, p_means, weighted_avg = calc_correlation_aggregates(cluster_sizes, r_values, p_values)
    print('Cluster sizes:', cluster_sizes)
    print_list_rounded('r (mean):', means)
    print_list_rounded('r (std) :', stds)
    print_list_rounded('p (mean):', p_means)
    print(f'r (weighted avg of means): {weighted_avg:.3f}')
