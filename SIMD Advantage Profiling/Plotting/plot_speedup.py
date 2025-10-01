import pandas as pd
import matplotlib.pyplot as plt

# Load data
df = pd.read_csv('combined_results.csv')

# Calculate mean and standard deviation for each kernel and size
summary = df.groupby(['Kernel', 'Size', 'Vectorization']).agg({
    'GFLOPs': ['mean', 'std'],
    'Time_ns': ['mean', 'std']
}).reset_index()

# Save summary to CSV
summary.to_csv('summary_results.csv', index=False)

# Create plots with error bars
for kernel in df['Kernel'].unique():
    kernel_data = summary[summary['Kernel'] == kernel]
    
    plt.figure(figsize=(10, 6))
    for vec in kernel_data['Vectorization'].unique():
        vec_data = kernel_data[kernel_data['Vectorization'] == vec]
        plt.errorbar(vec_data['Size'], vec_data[('GFLOPs', 'mean')], 
                     yerr=vec_data[('GFLOPs', 'std')], 
                     label=f'{kernel} - {vec}', capsize=5)
    
    plt.xscale('log')
    plt.xlabel('Array Size')
    plt.ylabel('GFLOP/s')
    plt.title(f'Performance of {kernel} Kernel')
    plt.legend()
    plt.grid(True, which="both", ls="--")
    plt.savefig(f'{kernel}_performance.png')
    plt.close()