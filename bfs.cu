#include <stdio.h>
#include <stdlib.h>
#include <iostream>
#include <vector>
#include <fstream>
#include <cuda_runtime.h>
#define N 10
#define BLOCK_SIZE 1024

using namespace std;

__global__ void bfs(int endNode, int* neighbour_array, int* offset, int* visited, int* q, int* prev)
{
  int i = blockDim.x * blockIdx.x + threadIdx.x;
      if(i == 1024){
        i = 0;
      }
      if (q[i] != -1) {
          int currentNode = q[i];
              for(int y = offset[i]; y < offset[i+1]; y++){
                  int neighbour = neighbour_array[y];
                  if (visited[neighbour] == 0) {
                      visited[neighbour] = 1;
                      q[neighbour] = neighbour;
                      prev[neighbour] = currentNode;
                  }
              }
      }
}


void edgeStreamToCSR(std::vector<int>& neighbour, std::vector<int>& offset)
{
    std::ifstream inputFile("output.txt");
    vector<vector<int>> adjlist;

    if(!inputFile) {
        std::cerr <<"Unable to open file for reading\n";
    }
    int numVertices, numEdges;
    inputFile >> numVertices >> numEdges;

    int u, v;

    for(int i = 0; i < numVertices; ++i) {
       adjlist.push_back(std::vector<int>());
    }

    for(int i = 0; i < numEdges; ++i) {
        inputFile >> u >> v;
        adjlist[u].push_back(v);
        adjlist[v].push_back(u);
    }
    offset.resize(numVertices + 1);

    offset[0] = 0;

    for(int i = 0; i < adjlist.size(); ++i) {
        offset[i+1] = offset[i] + adjlist[i].size();
        for(int j = 0; j < adjlist[i].size(); ++j) {
            neighbour.push_back(adjlist[i][j]);
        }
    }
}

void createInputGraph(int width, int depth, int& numVertices, int& numEdges, std::vector<int>& neighbour, vector<int>& offset)
{
    std::ofstream outFile("output.txt");
    if (!outFile) {
        std::cerr << "Error: Unable to create file. \n";
    }

    numEdges = width*depth;
    numVertices = numEdges + 1;

    outFile << numVertices <<" " << numEdges << std::endl;
    for(int i = 1; i <= width; ++i)
        outFile << "0" <<" " << i << std::endl;
    depth--;

    int start_index;
    int itr_num = 0;

    while(depth--) {
        start_index = width * itr_num;

        for(int i = 1; i <= width; ++i) {
            outFile << start_index + i << " " << start_index + i + width << std::endl;
            //std::cout << start_index + i << " " << start_index + i + width << std::endl;
        }
        itr_num++;
    }

    outFile.close();


    edgeStreamToCSR(neighbour, offset);

}

/*void bfs(vector<vector<int> >& adjList, int startNode, vector<bool>& visited)
{
    queue<int> q;
    visited[startNode] = true;
    q.push(startNode);
    while (!q.empty()) {
        int currentNode = q.front();
        q.pop();
        cout << currentNode << " ";
        for (int neighbor : adjList[currentNode]) {
            if (!visited[neighbor]) {
                visited[neighbor] = true;
                q.push(neighbor);
            }
        }
    }
}*/

int main() {

    cudaEvent_t start, stop;
    cudaEventCreate(&start);
    cudaEventCreate(&stop);
    float time;

    int width = 33;
    int depth = 33;

    int startNode = 0;
    int endNode = width*depth;

    std::vector<int> neighbour;
    std::vector<int> offset;
    std::vector<int> q;
    cudaError_t status = cudaSuccess;

    int threadsPerBlock;
    int blocksPerGrid;

    threadsPerBlock = BLOCK_SIZE;

    blocksPerGrid = 1;

    int numVertices, numEdges;
    createInputGraph(width, depth, numVertices, numEdges, neighbour, offset);

    int *visited = (int *)malloc(numVertices * sizeof(int));
    int *prev = (int *)malloc(numVertices * sizeof(int));

    for (int i=0; i<numVertices; i++)
    {
      visited[i] = 0;
      prev[i] = -1;
    }
    for (int i=0; i<numVertices; i++)
    {
      q.push_back(-1);
    }
    q[0] = 0;
    visited[0] = 1;
    prev[0] = 0;

    int *neighbourD = NULL;
    int *offsetD = NULL;
    int *visitedD = NULL;
    int *qD = NULL;
    int *prevD = NULL;
    std::size_t neighbour_size = sizeof(int) * neighbour.size();
    std::size_t offset_size = sizeof(int) * offset.size();
    std::size_t visited_size = sizeof(int) * numVertices;
    std::size_t q_size = sizeof(int) * q.size();
    std::size_t prev_size = sizeof(int) * numVertices;

    status = cudaMalloc((void **)&neighbourD, neighbour_size);
    status = cudaMalloc((void **)&offsetD, offset_size);
    status = cudaMalloc((void **)&visitedD, visited_size);
    status = cudaMalloc((void **)&qD, q_size);
    status = cudaMalloc((void **)&prevD, prev_size);

    cudaMemcpy(neighbourD, neighbour.data(), neighbour_size, cudaMemcpyHostToDevice);
    cudaMemcpy(offsetD, offset.data(), offset_size, cudaMemcpyHostToDevice);
    cudaMemcpy(visitedD, visited, visited_size, cudaMemcpyHostToDevice);
    cudaMemcpy(qD, q.data(), q_size, cudaMemcpyHostToDevice);
    cudaMemcpy(prevD, prev, prev_size, cudaMemcpyHostToDevice);

    cudaEventRecord(start,0);

    while(visited[endNode] != 1){
        bfs<<<blocksPerGrid, threadsPerBlock>>>(endNode, neighbourD, offsetD, visitedD, qD, prevD);
        cudaMemcpy(visited, visitedD, visited_size, cudaMemcpyDeviceToHost);
    }

    cudaEventRecord(stop,0);
    cudaEventSynchronize (stop);
    cudaEventElapsedTime (&time, start, stop);

    cudaEventDestroy (start);
    cudaEventDestroy (stop);
    cout<<"Time taken : "<<time<<" milli seconds"<<endl;

    //cudaMemcpy(visited, visitedD, visited_size, cudaMemcpyDeviceToHost);
    cudaMemcpy(prev, prevD, prev_size, cudaMemcpyDeviceToHost);

    int current = prev[endNode];
    printf("%d --> ", endNode);
    for(int i = 0; i<prev_size; i++){
        if(current != startNode){
            printf("%d --> ", current);
            current = prev[current];
        }
    }
    printf("%d ", startNode);

    return EXIT_SUCCESS;
}
