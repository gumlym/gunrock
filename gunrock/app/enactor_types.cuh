// ----------------------------------------------------------------
// Gunrock -- Fast and Efficient GPU Graph Library
// ----------------------------------------------------------------
// This source code is distributed under the terms of LICENSE.TXT
// in the root directory of this source distribution.
// ----------------------------------------------------------------

/**
 * @file
 * enactor_types.cuh
 *
 * @brief type defines for enactor base
 */

#pragma once

#include <moderngpu.cuh>

using namespace mgpu;

/* this is the "stringize macro macro" hack */
#define STR(x) #x
#define XSTR(x) STR(x)

namespace gunrock {
namespace app {

/*
 * @brief Accumulate number function.
 *
 * @tparam SizeT1
 * @tparam SizeT2
 *
 * @param[in] num
 * @param[in] sum
 */
template <typename SizeT1, typename SizeT2>
__global__ void Accumulate_Num (
    SizeT1 *num,
    SizeT2 *sum)
{
    sum[0]+=num[0];
}

/**
 * @brief Structure for auxiliary variables used in enactor.
 */
template <typename SizeT>
struct EnactorStats
{
    long long                        iteration           ;
    unsigned long long               total_lifetimes     ;
    unsigned long long               total_runtimes      ;
    util::Array1D<int, SizeT>        edges_queued        ;
    util::Array1D<int, SizeT>        nodes_queued        ;
    std::vector<float>         per_iteration_advance_time;
    std::vector<float>         per_iteration_advance_mteps;
    std::vector<int>         per_iteration_advance_input_edges;
    std::vector<int>         per_iteration_advance_output_edges;
    std::vector<bool>         per_iteration_advance_direction;
    unsigned int                     advance_grid_size   ;
    unsigned int                     filter_grid_size    ;
    util::KernelRuntimeStatsLifetime advance_kernel_stats;
    util::KernelRuntimeStatsLifetime filter_kernel_stats ;
    util::Array1D<int, SizeT>        node_locks          ;
    util::Array1D<int, SizeT>        node_locks_out      ;
    cudaError_t                      retval              ;
    clock_t                          start_time          ;

    /*
     * @brief Default EnactorStats constructor
     */
    EnactorStats():
        iteration       (0),
        total_lifetimes (0),
        total_runtimes  (0),
        retval          (cudaSuccess)
    {
        node_locks    .SetName("node_locks"    );
        node_locks_out.SetName("node_locks_out");
        edges_queued  .SetName("edges_queued");
        nodes_queued  .SetName("nodes_queued");
    }

    /*
     * @brief Accumulate edge function.
     *
     * @tparam SizeT2
     *
     * @param[in] d_queue Pointer to the queue
     * @param[in] stream CUDA stream
     */
    template <typename SizeT2>
    void AccumulateEdges(SizeT2 *d_queued, cudaStream_t stream)
    {
        Accumulate_Num<<<1,1,0,stream>>> (
            d_queued, edges_queued.GetPointer(util::DEVICE));
    }

    /*
     * @brief Accumulate node function.
     *
     * @tparam SizeT2
     *
     * @param[in] d_queue Pointer to the queue
     * @param[in] stream CUDA stream
     */
    template <typename SizeT2>
    void AccumulateNodes(SizeT2 *d_queued, cudaStream_t stream)
    {
        Accumulate_Num<<<1,1,0,stream>>> (
            d_queued, nodes_queued.GetPointer(util::DEVICE));
    }

    cudaError_t Init(
        //int max_grid_size,
        //int advance_occupancy,
        //int filter_occupancy,
        int node_lock_size = 1024)
   {
        cudaError_t retval = cudaSuccess;
        if (retval = advance_kernel_stats
              .Setup(advance_grid_size)) return retval;
        if (retval = filter_kernel_stats
              .Setup(filter_grid_size )) return retval;
        if (retval = node_locks
              .Allocate(node_lock_size + 1, util::DEVICE)) return retval;
        if (retval = node_locks_out
              .Allocate(node_lock_size + 1, util::DEVICE)) return retval;
        if (retval = nodes_queued
              .Allocate(1, util::DEVICE | util::HOST)) return retval;
        if (retval = edges_queued
              .Allocate(1, util::DEVICE | util::HOST)) return retval;
        return retval;
    }

    cudaError_t Reset()
    {
        iteration       = 0;
        total_lifetimes = 0;
        total_runtimes  = 0;
        retval          = cudaSuccess;

        nodes_queued[0] = 0;
        edges_queued[0] = 0;
        nodes_queued.Move(util::HOST, util::DEVICE);
        edges_queued.Move(util::HOST, util::DEVICE);

        return retval;
    }

    cudaError_t Release()
    {
        cudaError_t retval = cudaSuccess;
        if (retval = node_locks    .Release()) return retval;
        if (retval = node_locks_out.Release()) return retval;
        if (retval = edges_queued  .Release()) return retval;
        if (retval = nodes_queued  .Release()) return retval;
        return retval;
    }
};

/**
 * @brief Structure for auxiliary variables used in frontier operations.
 */
template <typename SizeT>
struct FrontierAttribute
{
    SizeT        queue_length ;
    util::Array1D<SizeT,SizeT>
                 output_length;
    unsigned int queue_index  ;
    SizeT        queue_offset ;
    int          selector     ;
    bool         queue_reset  ;
    int          current_label;
    bool         has_incoming ;
    gunrock::oprtr::advance::TYPE
                 advance_type ;

    /*
     * @brief Default FrontierAttribute constructor
     */
    FrontierAttribute() :
        queue_length (0),
        queue_index  (0),
        queue_offset (0),
        selector     (0),
        queue_reset  (false),
        has_incoming (false)
    {
        output_length.SetName("output_length");
    }

    virtual ~FrontierAttribute()
    {
        Release();
    }

    cudaError_t Release()
    {
        cudaError_t retval = cudaSuccess;
        if (retval = output_length.Release())
            return retval;
        return retval;
    }

    cudaError_t Init()
    {
        cudaError_t retval = cudaSuccess;
        if (retval = output_length.Init(1, util::HOST | util::DEVICE, true))
            return retval;
        return retval;
    }

    cudaError_t Reset()
    {
        cudaError_t retval = cudaSuccess;
        queue_length  = 0;
        queue_index   = 0;
        queue_offset  = 0;
        selector      = 0;
        queue_reset   = false;
        has_incoming  = false;
        output_length[0] = 0;
        if (retval = output_length.Move(util::HOST, util::DEVICE))
            return retval;
        return retval;
    }
};

/*
 * @brief Thread slice data structure
 */
class ThreadSlice
{
public:
    enum Status {
        New,
        Inited,
        Start,
        Wait,
        Running,
        Idle,
        ToKill,
        Ended
    };

    int           thread_num ;
    int           init_size  ;
    CUTThread     thread_Id  ;
    Status        status     ;
    void         *problem    ;
    void         *enactor    ;
    ContextPtr   *context    ;
    //util::cpu_mt::CPUBarrier
    //             *cpu_barrier;

    /*
     * @brief Default ThreadSlice constructor
     */
    ThreadSlice() :
        problem     (NULL),
        enactor     (NULL),
        context     (NULL),
        thread_num  (0   ),
        init_size   (0   ),
        status      (Status::New)
        //cpu_barrier (NULL)
    {
    }

    /*
     * @brief Default ThreadSlice destructor
     */
    virtual ~ThreadSlice()
    {
        problem     = NULL;
        enactor     = NULL;
        context     = NULL;
        //cpu_barrier = NULL;
    }

    cudaError_t Reset()
    {
        cudaError_t retval = cudaSuccess;
        init_size = 0;
        return retval;
    }
};

} // namespace app
} // namespace gunrock

// Leave this at the end of the file
// Local Variables:
// mode:c++
// c-file-style: "NVIDIA"
// End:
